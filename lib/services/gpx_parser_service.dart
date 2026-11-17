import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/gp_score.dart';
import '../models/gp_track.dart';
import '../models/master_bar_event.dart';
import '../utils/play_order.dart';

/// A user-presentable parse failure (no "Exception:" prefix in the UI).
class GpParseException implements Exception {
  final String message;
  const GpParseException(this.message);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Intermediate (track independent) representations
// ---------------------------------------------------------------------------

class _RawNote {
  int? stringIndex; // 0 = LOWEST string of the track
  int? fret;
  int? midi;
  int? articulation; // drums: -1 = placeholder, not a real hit
  bool tieDestination = false;
  bool tieOrigin = false;
  bool letRing = false;
  bool muted = false;
  bool palmMute = false;
  bool hopoOrigin = false;
  bool hopoDestination = false;
  bool tap = false;
  bool ghost = false;
  String? harmonicType;
  double? harmonicFret;
  int slideFlags = 0;
  GpBend? bend;
  GpVibrato? vibrato;
}

class _RawBeat {
  final List<String> noteIds;
  final double quarters;
  final bool isGrace;
  final StrumDirection strum;
  const _RawBeat(this.noteIds, this.quarters, this.isGrace, this.strum);
}

class _TempoAutomation {
  final int bar;
  final double position; // 0..1 inside the bar
  final double bpm; // quarter-note BPM
  const _TempoAutomation(this.bar, this.position, this.bpm);
}

class _TrackInfo {
  String name = 'Track';
  bool isPercussion = false;
  List<int> tuning = const [];
  int capo = 0;
  int firstStaffIndex = 0;
}

class GpxParserService {
  GpxParserService._();

  // -------------------------------------------------------------------------
  // File picking / isolate plumbing
  // -------------------------------------------------------------------------

  static Future<GpScore?> pickAndParse() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final String lower = file.name.toLowerCase();
    if (!lower.endsWith('.gp') && !lower.endsWith('.gpx')) {
      throw const GpParseException('Please select a Guitar Pro 7/8 file (.gp).');
    }

    // Parse BEFORE touching the persistent copy so that a bad file never
    // overwrites a good one with the same name.
    final List<int>? bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) throw const GpParseException('Could not read the selected file.');

    final docsDir = await getApplicationDocumentsDirectory();
    final String persistentPath = '${docsDir.path}/${file.name}';
    final score = await _parseInIsolate(file.name, persistentPath, bytes);
    await File(persistentPath).writeAsBytes(bytes, flush: true);
    return score;
  }

  static Future<GpScore> parseGpFile(String fileName, String? path, List<int>? bytesData) async {
    List<int> bytes;
    if (path != null && await File(path).exists()) {
      bytes = await File(path).readAsBytes();
    } else if (bytesData != null) {
      bytes = bytesData;
    } else {
      throw const GpParseException('Could not read file data.');
    }
    return _parseInIsolate(fileName, path ?? '', bytes);
  }

  static Future<GpScore> _parseInIsolate(String fileName, String path, List<int> bytes) {
    return Isolate.run(() => parseBytes(bytes, fileName: fileName, filePath: path));
  }

  // -------------------------------------------------------------------------
  // Pure, synchronous entry points (used by the isolate and by tests)
  // -------------------------------------------------------------------------

  /// Parses the raw bytes of a `.gp` file (a zip archive containing
  /// `Content/score.gpif`).
  static GpScore parseBytes(List<int> bytes, {String fileName = '', String filePath = ''}) {
    final String? unsupported = _unsupportedFormatMessage(bytes);
    if (unsupported != null) throw GpParseException(unsupported);

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const GpParseException('Invalid GP file. Please use a Guitar Pro 7/8 (.gp) file.');
    }

    ArchiveFile? gpifFile;
    for (final file in archive) {
      if (file.name.split('/').last.toLowerCase() == 'score.gpif') {
        gpifFile = file;
        break;
      }
    }
    if (gpifFile == null) {
      throw const GpParseException('Invalid .gp file: score.gpif was not found.');
    }

    final dynamic raw = gpifFile.content;
    final List<int> data = raw is List<int> ? raw : List<int>.from(raw as Iterable);
    // GPIF is UTF-8. String.fromCharCodes garbled accented titles.
    String xml = utf8.decode(data, allowMalformed: true);
    if (xml.isNotEmpty && xml.codeUnitAt(0) == 0xFEFF) xml = xml.substring(1);
    return parseGpifXml(xml, fileName: fileName, filePath: filePath);
  }

  static String? _unsupportedFormatMessage(List<int> bytes) {
    if (bytes.length < 4) return 'The file is empty or corrupted.';
    final String head = String.fromCharCodes(bytes.take(4));
    if (head == 'BCFZ' || head == 'BCFS') {
      return 'Guitar Pro 6 (.gpx) files are not supported. Open the song in Guitar Pro 7/8 and save it as .gp.';
    }
    if (bytes.length > 20 && String.fromCharCodes(bytes.sublist(1, min(bytes.length, 20))).contains('FICHIER GUITAR PRO')) {
      return 'Guitar Pro 3/4/5 files are not supported. Open the song in Guitar Pro 7/8 and save it as .gp.';
    }
    return null;
  }

  /// Parses the text of a GPIF document.
  static GpScore parseGpifXml(String xml, {String fileName = '', String filePath = ''}) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException {
      throw const GpParseException('The score data inside this file is corrupted.');
    }

    final XmlElement? scoreEl = document.findAllElements('Score').firstOrNull;
    final String title = scoreEl?.getElement('Title')?.innerText.trim() ?? '';
    final String artist = scoreEl?.getElement('Artist')?.innerText.trim() ?? '';

    final List<MasterBarEvent> masterBars = _parseMasterBars(document);
    final List<int> playOrder = computePlayOrder(masterBars);
    final List<GpTrack> tracks = _parseTracks(document, masterBars);

    final int firstSixteenths = masterBars.isNotEmpty ? masterBars.first.sixteenthCount : 16;
    return GpScore(
      fileName: fileName,
      filePath: filePath,
      title: title.isEmpty && artist.isEmpty ? 'Unknown Title' : title,
      artist: artist,
      tempo: masterBars.isNotEmpty ? masterBars.first.tempo : 120,
      notesPerMeasure: firstSixteenths > 0 ? firstSixteenths : 16,
      masterBars: masterBars,
      playOrder: playOrder,
      tracks: tracks,
    );
  }

  // -------------------------------------------------------------------------
  // Small XML helpers
  // -------------------------------------------------------------------------

  static Map<String, XmlElement> _props(XmlElement owner) {
    final Map<String, XmlElement> map = {};
    final XmlElement? props = owner.getElement('Properties');
    if (props == null) return map;
    for (final XmlElement p in props.findElements('Property')) {
      final String? name = p.getAttribute('name');
      if (name != null) map[name] = p;
    }
    return map;
  }

  /// Text of the first child element of a `<Property>` (e.g. `<Fret>5</Fret>`).
  static String? _propValue(Map<String, XmlElement> props, String name) {
    final XmlElement? p = props[name];
    if (p == null) return null;
    for (final XmlElement c in p.childElements) {
      return c.innerText.trim();
    }
    return null;
  }

  /// GPIF flags are written as `<Property name="X"><Enable/></Property>`.
  static bool _flag(Map<String, XmlElement> props, String name) {
    final XmlElement? p = props[name];
    if (p == null) return false;
    for (final XmlElement c in p.childElements) {
      final String t = c.innerText.trim().toLowerCase();
      if (t == 'false' || t == '0') return false;
    }
    return true;
  }

  static List<String> _ids(String? text) =>
      (text ?? '').trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

  // -------------------------------------------------------------------------
  // Master bars, tempo map, repeats
  // -------------------------------------------------------------------------

  /// Multiplier that converts the tempo reference unit of an automation
  /// ("120 2") to quarter-note BPM. 2 = quarter note.
  static double _tempoUnitFactor(String? unit) {
    switch (unit) {
      case '1':
        return 0.5; // eighth
      case '3':
        return 1.5; // dotted quarter
      case '4':
        return 2.0; // half
      case '5':
        return 3.0; // dotted half
      default:
        return 1.0;
    }
  }

  static List<_TempoAutomation> _readTempoAutomations(XmlDocument document) {
    final XmlElement? master = document.findAllElements('MasterTrack').firstOrNull;
    final Iterable<XmlElement> nodes =
        (master ?? document.rootElement).findAllElements('Automation');
    final List<_TempoAutomation> out = [];
    for (final XmlElement a in nodes) {
      if (a.getElement('Type')?.innerText.trim() != 'Tempo') continue;
      final List<String> parts = (a.getElement('Value')?.innerText ?? '').trim().split(RegExp(r'\s+'));
      final double? bpm = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
      final int? bar = int.tryParse(a.getElement('Bar')?.innerText.trim() ?? '');
      if (bpm == null || bpm <= 0 || bar == null) continue;
      final double pos = double.tryParse(a.getElement('Position')?.innerText.trim() ?? '') ?? 0.0;
      out.add(_TempoAutomation(bar, pos.clamp(0.0, 1.0).toDouble(), bpm * _tempoUnitFactor(parts.length > 1 ? parts[1] : null)));
    }
    out.sort((a, b) {
      final int c = a.bar.compareTo(b.bar);
      return c != 0 ? c : a.position.compareTo(b.position);
    });
    return out;
  }

  static List<MasterBarEvent> _parseMasterBars(XmlDocument document) {
    final List<XmlElement> nodes = document.findAllElements('MasterBar').toList();
    final List<_TempoAutomation> autos = _readTempoAutomations(document);

    final List<MasterBarEvent> events = [];
    double carryTempo = autos.isNotEmpty ? autos.first.bpm : 120.0;
    int numerator = 4;
    int denominator = 4;
    int cumulativeTick = 0;
    double cumulativeMs = 0.0;

    for (int i = 0; i < nodes.length; i++) {
      final XmlElement mb = nodes[i];

      final String? timeText = mb.getElement('Time')?.innerText.trim();
      if (timeText != null && timeText.contains('/')) {
        final List<String> parts = timeText.split('/');
        final int? n = int.tryParse(parts[0]);
        final int? d = int.tryParse(parts[1]);
        if (n != null && n > 0 && d != null && d > 0) {
          numerator = n;
          denominator = d;
        }
      }

      // Tempo segments: the tempo carried over from the previous bar, then any
      // automation of this bar (Position is a 0..1 ratio inside the bar).
      final List<TempoChange> changes = [TempoChange(ratio: 0.0, bpm: carryTempo)];
      for (final _TempoAutomation a in autos.where((a) => a.bar == i)) {
        if (a.position <= 0.0001) {
          changes[0] = TempoChange(ratio: 0.0, bpm: a.bpm);
        } else {
          changes.add(TempoChange(ratio: a.position, bpm: a.bpm));
        }
      }
      changes.sort((a, b) => a.ratio.compareTo(b.ratio));
      carryTempo = changes.last.bpm;

      final XmlElement? repeat = mb.getElement('Repeat');
      final bool repeatStart = repeat?.getAttribute('start')?.toLowerCase() == 'true';
      final bool repeatEnd = repeat?.getAttribute('end')?.toLowerCase() == 'true';
      final int repeatCount = int.tryParse(repeat?.getAttribute('count') ?? '') ?? 0;
      final List<int> alternate = _ids(mb.getElement('AlternateEndings')?.innerText)
          .map(int.tryParse)
          .whereType<int>()
          .toList();

      final double quarters = numerator * (4.0 / denominator);
      final MasterBarEvent probe = MasterBarEvent(
        barIndex: i,
        tempo: changes.first.bpm.round(),
        numerator: numerator,
        denominator: denominator,
        startTick: cumulativeTick,
        startMs: cumulativeMs,
        durationMs: 0,
        tempoChanges: changes,
      );
      final double durationMs = probe.quartersToMs(quarters);

      events.add(MasterBarEvent(
        barIndex: i,
        tempo: changes.first.bpm.round(),
        numerator: numerator,
        denominator: denominator,
        startTick: cumulativeTick,
        startMs: cumulativeMs,
        durationMs: durationMs,
        tripletFeel: mb.getElement('TripletFeel')?.innerText.trim() ?? '',
        tempoChanges: changes,
        isRepeatStart: repeatStart,
        isRepeatEnd: repeatEnd,
        repeatCount: repeatCount,
        alternateEndings: alternate,
      ));
      cumulativeTick += (quarters * 960).round();
      cumulativeMs += durationMs;
    }
    return events;
  }

  // -------------------------------------------------------------------------
  // Tracks
  // -------------------------------------------------------------------------

  static double _rhythmQuarters(XmlElement rhythm) {
    final String noteVal = rhythm.getElement('NoteValue')?.innerText.trim() ?? 'Quarter';
    double val;
    switch (noteVal) {
      case 'Long':
        val = 16.0;
        break;
      case 'Breve':
        val = 8.0;
        break;
      case 'Whole':
        val = 4.0;
        break;
      case 'Half':
        val = 2.0;
        break;
      case '8th':
      case 'Eighth':
        val = 0.5;
        break;
      case '16th':
        val = 0.25;
        break;
      case '32nd':
        val = 0.125;
        break;
      case '64th':
        val = 0.0625;
        break;
      case '128th':
        val = 0.03125;
        break;
      default:
        val = 1.0;
    }
    final int dots = int.tryParse(rhythm.getElement('AugmentationDot')?.getAttribute('count') ?? '0') ?? 0;
    double dotted = val;
    double add = val;
    for (int d = 0; d < dots; d++) {
      add /= 2;
      dotted += add;
    }
    val = dotted;
    final XmlElement? tuplet = rhythm.getElement('PrimaryTuplet');
    if (tuplet != null) {
      final int num = int.tryParse(tuplet.getAttribute('num') ?? '') ?? 3;
      final int den = int.tryParse(tuplet.getAttribute('den') ?? '') ?? 2;
      if (num > 0) val *= den / num;
    }
    return val;
  }

  /// Semitones above the OPEN string of a natural harmonic at [fret].
  static int _naturalHarmonicInterval(double fret) {
    switch (fret.round()) {
      case 12:
        return 12;
      case 7:
      case 19:
        return 19;
      case 5:
      case 24:
        return 24;
      case 4:
      case 9:
      case 16:
        return 28;
      case 3:
        return 31;
      default:
        return 12;
    }
  }

  static _RawNote _parseNote(XmlElement note) {
    final Map<String, XmlElement> props = _props(note);
    final _RawNote n = _RawNote();

    n.stringIndex = int.tryParse(_propValue(props, 'String') ?? '');
    n.fret = int.tryParse(_propValue(props, 'Fret') ?? '');
    n.midi = int.tryParse(_propValue(props, 'Midi') ?? '');
    n.articulation = int.tryParse(note.getElement('InstrumentArticulation')?.innerText.trim() ?? '');

    // Only the DESTINATION of a tie is silent / re-uses the previous attack.
    final XmlElement? tie = note.getElement('Tie');
    if (tie != null) {
      n.tieOrigin = tie.getAttribute('origin')?.toLowerCase() == 'true';
      n.tieDestination = tie.getAttribute('destination')?.toLowerCase() == 'true';
    }

    n.letRing = note.getElement('LetRing') != null || _flag(props, 'LetRing');
    n.muted = _flag(props, 'Muted');
    n.palmMute = _flag(props, 'PalmMuted');
    n.tap = _flag(props, 'Tapped');
    n.hopoOrigin = _flag(props, 'HopoOrigin');
    n.hopoDestination = _flag(props, 'HopoDestination');
    // GP7/8 write ghost notes as <AntiAccent>Normal</AntiAccent>.
    n.ghost = note.getElement('AntiAccent')?.innerText.trim().toLowerCase() == 'normal' || _flag(props, 'Ghost');

    n.harmonicType = _propValue(props, 'HarmonicType')?.toLowerCase();
    n.harmonicFret = double.tryParse(_propValue(props, 'HarmonicFret') ?? '');
    n.slideFlags = int.tryParse(_propValue(props, 'Slide') ?? '') ?? 0;
    n.bend = _parseBend(props);

    final String? vib = note.getElement('Vibrato')?.innerText.trim().toLowerCase();
    if (vib != null) {
      n.vibrato = GpVibrato(amplitude: vib == 'wide' ? 2.0 : 1.0);
    }
    return n;
  }

  /// GP7/8 bend envelope. Values are in 1/50 semitone (100 = full-step bend,
  /// 25 = quarter-tone bend); offsets are 0..100 percent of the note length.
  static GpBend? _parseBend(Map<String, XmlElement> props) {
    double? f(String name) => double.tryParse(_propValue(props, name) ?? '');

    final double? originValue = f('BendOriginValue');
    final double? middleValue = f('BendMiddleValue');
    final double? destValue = f('BendDestinationValue');
    if (originValue == null && middleValue == null && destValue == null) return null;

    final List<BendPoint> points = [];
    void add(double? offsetPercent, double? value) {
      if (value == null) return;
      points.add(BendPoint(
        position: ((offsetPercent ?? 0.0) / 100.0).clamp(0.0, 1.0).toDouble(),
        offset: max(0.0, value / 50.0),
      ));
    }

    add(f('BendOriginOffset') ?? 0.0, originValue ?? 0.0);
    if (middleValue != null) {
      final double? m1 = f('BendMiddleOffset1');
      final double? m2 = f('BendMiddleOffset2');
      add(m1 ?? 50.0, middleValue);
      if (m2 != null && m1 != null && (m2 - m1).abs() > 0.01) add(m2, middleValue);
    }
    add(f('BendDestinationOffset') ?? 100.0, destValue);

    points.sort((a, b) => a.position.compareTo(b.position));
    double maxOffset = 0.0;
    for (final BendPoint p in points) {
      if (p.offset > maxOffset) maxOffset = p.offset;
    }
    if (maxOffset <= 0.0) return null;
    return GpBend(maximumPitchOffset: maxOffset, envelope: points);
  }

  static SlideType _slideFromFlags(int flags) {
    if (flags & 1 != 0) return SlideType.shift;
    if (flags & 2 != 0) return SlideType.legato;
    if (flags & 4 != 0) return SlideType.outDownwards;
    if (flags & 8 != 0) return SlideType.outUpwards;
    if (flags & 16 != 0) return SlideType.intoFromBelow;
    if (flags & 32 != 0) return SlideType.intoFromAbove;
    return SlideType.none;
  }

  /// Display lane (1..6) for a General MIDI drum note.
  static int _drumLane(int midi) {
    switch (midi) {
      case 35:
      case 36:
        return 6; // kick
      case 41:
      case 43:
      case 45:
        return 5; // floor / low toms
      case 38:
      case 37:
      case 39:
      case 40:
        return 4; // snare, rim, clap
      case 47:
      case 48:
      case 50:
        return 3; // mid / high toms
      case 42:
      case 44:
      case 46:
        return 2; // hi-hat family
      default:
        return 1; // cymbals and everything else
    }
  }

  static GpNote _buildNote(_RawNote raw, _TrackInfo info) {
    if (info.isPercussion) {
      final int midi = raw.midi ?? 38;
      return GpNote(
        stringNum: _drumLane(midi),
        fretNum: 0,
        pitch: midi,
        isPercussion: true,
        isGhost: raw.ghost,
        isTie: raw.tieDestination,
        isTieOrigin: raw.tieOrigin,
      );
    }

    final List<int> tuning = info.tuning;
    final int? s = raw.stringIndex;
    final int? fret = raw.fret;

    int displayString;
    int fretNum;
    int pitch;
    if (s != null && fret != null) {
      final int stringCount = tuning.isNotEmpty ? tuning.length : 6;
      displayString = max(1, stringCount - s);
      fretNum = fret;
      if (tuning.isNotEmpty && s >= 0 && s < tuning.length) {
        pitch = tuning[s] + fret + info.capo;
      } else if (raw.midi != null) {
        pitch = raw.midi!;
      } else {
        const List<int> std = [40, 45, 50, 55, 59, 64];
        pitch = (s >= 0 && s < std.length ? std[s] : 40) + fret + info.capo;
      }
    } else {
      // Pitch-only note (e.g. keyboard): keep it audible.
      displayString = 1;
      pitch = raw.midi ?? 60;
      fretNum = pitch;
    }

    HarmonicType harmonic = HarmonicType.none;
    final String? ht = raw.harmonicType;
    if (ht != null && ht != 'none') {
      if (ht == 'natural') {
        harmonic = HarmonicType.natural;
        final double hf = raw.harmonicFret ?? fretNum.toDouble();
        final int open = pitch - fretNum;
        pitch = open + _naturalHarmonicInterval(hf);
      } else {
        harmonic = ht == 'pinch' || ht == 'semi' ? HarmonicType.pinch : HarmonicType.artificial;
        final double hf = raw.harmonicFret ?? 12.0;
        pitch += _naturalHarmonicInterval(hf);
      }
    }

    return GpNote(
      stringNum: displayString,
      fretNum: fretNum,
      pitch: pitch.clamp(0, 127),
      isTie: raw.tieDestination,
      isTieOrigin: raw.tieOrigin,
      isLetRing: raw.letRing,
      isMuted: raw.muted,
      isPalmMute: raw.palmMute,
      isLegato: raw.hopoDestination,
      isHopoOrigin: raw.hopoOrigin,
      isGhost: raw.ghost,
      isTap: raw.tap,
      harmonicType: harmonic,
      slideType: _slideFromFlags(raw.slideFlags),
      bend: raw.bend,
      vibrato: raw.vibrato,
    );
  }

  /// Swing description for a triplet-feel name: (unit in quarters, long ratio).
  static ({double unit, double longRatio})? _swingFor(String feel) {
    switch (feel) {
      case 'Triplet8th':
        return (unit: 0.5, longRatio: 4.0 / 3.0);
      case 'Triplet16th':
        return (unit: 0.25, longRatio: 4.0 / 3.0);
      case 'Dotted8th':
        return (unit: 0.5, longRatio: 1.5);
      case 'Dotted16th':
        return (unit: 0.25, longRatio: 1.5);
      default:
        return null;
    }
  }

  static List<GpTrack> _parseTracks(XmlDocument document, List<MasterBarEvent> masterBars) {
    // ---- Tracks (names, tuning, capo, percussion) ----
    // NOTE: <MasterTrack> also contains a text-only <Tracks>0 1 2</Tracks>
    // element, so look for <Track> elements directly.
    final List<XmlElement> trackElements = document.findAllElements('Track').toList();
    final List<_TrackInfo> infos = [];
    int staffCursor = 0;
    for (final XmlElement t in trackElements) {
      final _TrackInfo info = _TrackInfo();
      info.name = t.getElement('Name')?.innerText.trim() ?? 'Track';
      if (info.name.isEmpty) info.name = 'Track ${infos.length + 1}';

      final String instrumentType =
          t.getElement('InstrumentSet')?.getElement('Type')?.innerText.trim().toLowerCase() ?? '';
      info.isPercussion = instrumentType == 'drumkit' ||
          t.getElement('IsPercussion')?.innerText.trim().toLowerCase() == 'true' ||
          t.getElement('GeneralMidi')?.getElement('PrimaryChannel')?.innerText.trim() == '9';

      // GP7/8 keep tuning on the staff; older exports on the track.
      for (final XmlElement prop in t.findAllElements('Property')) {
        final String? name = prop.getAttribute('name');
        if (name == 'Tuning' && info.tuning.isEmpty) {
          final String? pitches = prop.getElement('Pitches')?.innerText;
          info.tuning = _ids(pitches).map(int.tryParse).whereType<int>().toList();
        } else if (name == 'CapoFret') {
          final String? c = prop.childElements.isNotEmpty ? prop.childElements.first.innerText.trim() : null;
          info.capo = int.tryParse(c ?? '') ?? info.capo;
        }
      }

      final int staffCount = max(1, t.getElement('Staves')?.findElements('Staff').length ?? 1);
      info.firstStaffIndex = staffCursor;
      staffCursor += staffCount;
      infos.add(info);
    }
    if (infos.isEmpty) {
      infos.add(_TrackInfo()..name = 'All Tracks');
    }

    // ---- Rhythms ----
    final Map<String, double> rhythmMap = {};
    for (final XmlElement rhythm in document.findAllElements('Rhythms').firstOrNull?.findElements('Rhythm') ?? <XmlElement>[]) {
      rhythmMap[rhythm.getAttribute('id') ?? ''] = _rhythmQuarters(rhythm);
    }

    // ---- Notes (raw, track independent) ----
    final Map<String, _RawNote> rawNotes = {};
    for (final XmlElement note in document.findAllElements('Notes').expand((e) => e.findElements('Note'))) {
      final String id = note.getAttribute('id') ?? '';
      if (id.isNotEmpty) rawNotes[id] = _parseNote(note);
    }
    // Some documents hold <Note> directly under <Notes> only once; fall back
    // to a global search when the structured lookup found nothing.
    if (rawNotes.isEmpty) {
      for (final XmlElement note in document.findAllElements('Note')) {
        final String id = note.getAttribute('id') ?? '';
        if (id.isNotEmpty) rawNotes[id] = _parseNote(note);
      }
    }

    // ---- Beats ----
    final Map<String, _RawBeat> rawBeats = {};
    for (final XmlElement beat in document.findAllElements('Beats').expand((e) => e.findElements('Beat'))) {
      final String id = beat.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final String ref = beat.getElement('Rhythm')?.getAttribute('ref') ?? '';
      final double quarters = rhythmMap[ref] ?? 1.0;
      // GP7/8: <Property name="Brush"><Direction>Down</Direction></Property>
      final String brush = (_propValue(_props(beat), 'Brush') ?? '').toLowerCase();
      rawBeats[id] = _RawBeat(
        _ids(beat.getElement('Notes')?.innerText),
        quarters,
        beat.getElement('GraceNotes') != null,
        brush == 'down' ? StrumDirection.down : (brush == 'up' ? StrumDirection.up : StrumDirection.none),
      );
    }

    // ---- Voices ----
    final Map<String, List<String>> voiceBeatIds = {};
    for (final XmlElement voice in document.findAllElements('Voices').expand((e) => e.findElements('Voice'))) {
      final String id = voice.getAttribute('id') ?? '';
      if (id.isNotEmpty) voiceBeatIds[id] = _ids(voice.getElement('Beats')?.innerText);
    }

    // ---- Bars ----
    final Map<String, List<String>> barVoiceIds = {};
    for (final XmlElement bar in document.findAllElements('Bars').expand((e) => e.findElements('Bar'))) {
      final String id = bar.getAttribute('id') ?? '';
      if (id.isNotEmpty) barVoiceIds[id] = _ids(bar.getElement('Voices')?.innerText);
    }

    // ---- Master bars -> per-track beats ----
    final List<XmlElement> masterBarNodes = document.findAllElements('MasterBar').toList();
    final List<List<GpBeat>> trackBeats = List.generate(infos.length, (_) => <GpBeat>[]);
    final List<List<int>> trackMeasureEnds = List.generate(infos.length, (_) => <int>[]);

    for (int b = 0; b < masterBarNodes.length; b++) {
      final MasterBarEvent mbe = masterBars[b];
      final List<String> barIds = _ids(masterBarNodes[b].getElement('Bars')?.innerText);
      final ({double unit, double longRatio})? swing = _swingFor(mbe.tripletFeel);

      for (int t = 0; t < infos.length; t++) {
        final _TrackInfo info = infos[t];
        final int staff = info.firstStaffIndex;
        final String? barId = staff < barIds.length ? barIds[staff] : null;
        final List<GpBeat> merged = _buildBarBeats(
          voiceIds: barId == null ? const [] : (barVoiceIds[barId] ?? const []),
          voiceBeatIds: voiceBeatIds,
          rawBeats: rawBeats,
          rawNotes: rawNotes,
          info: info,
          barQuarters: mbe.quarters,
          swing: swing,
        );
        trackBeats[t].addAll(merged);
        // Every master bar owns >= 1 beat, so this is exactly one per bar.
        trackMeasureEnds[t].add(trackBeats[t].length - 1);
      }
    }

    return [
      for (int t = 0; t < infos.length; t++)
        GpTrack(
          id: '$t',
          name: infos[t].name,
          beats: trackBeats[t],
          measureEndIndices: trackMeasureEnds[t],
          tuning: infos[t].tuning,
          capo: infos[t].capo,
          isPercussion: infos[t].isPercussion,
        ),
    ];
  }

  /// Merges all voices of one bar into a single beat list that always covers
  /// the full bar: empty / rest-only bars become one bar-long rest, short bars
  /// are padded with a trailing rest.
  static List<GpBeat> _buildBarBeats({
    required List<String> voiceIds,
    required Map<String, List<String>> voiceBeatIds,
    required Map<String, _RawBeat> rawBeats,
    required Map<String, _RawNote> rawNotes,
    required _TrackInfo info,
    required double barQuarters,
    required ({double unit, double longRatio})? swing,
  }) {
    const int ticksPerQuarter = 960;
    final Map<int, List<GpNote>> notesAt = {};
    final Map<int, double> durationAt = {};
    final Map<int, StrumDirection> strumAt = {};

    for (final String voiceId in voiceIds) {
      final List<String>? beatIds = voiceBeatIds[voiceId];
      if (beatIds == null) continue; // "-1" = unused voice
      double pos = 0.0;
      for (final String beatId in beatIds) {
        final _RawBeat? rb = rawBeats[beatId];
        if (rb == null || rb.isGrace) continue; // grace beats take no time
        final int key = (pos * ticksPerQuarter).round();
        final List<GpNote> list = notesAt.putIfAbsent(key, () => <GpNote>[]);
        durationAt.putIfAbsent(key, () => rb.quarters);
        if (rb.strum != StrumDirection.none) strumAt.putIfAbsent(key, () => rb.strum);
        for (final String nid in rb.noteIds) {
          final _RawNote? raw = rawNotes[nid];
          if (raw == null) continue;
          // Drum tracks contain placeholder notes (Midi 0, articulation -1)
          // that are not real hits; they would play as junk pitch 0.
          if (info.isPercussion && (raw.articulation == -1 || (raw.midi ?? 0) == 0)) continue;
          list.add(_buildNote(raw, info));
        }
        pos += rb.quarters;
      }
    }

    final bool hasAnyNote = notesAt.values.any((l) => l.isNotEmpty);
    if (!hasAnyNote) {
      // Empty bar, or rests only (a whole rest in 3/4 would otherwise be 4 beats).
      return [GpBeat.rest(duration: barQuarters)];
    }

    final List<int> keys = notesAt.keys.toList()..sort();
    final List<GpBeat> beats = [];
    double covered = 0.0;

    // Leading gap (a voice that does not start at position 0).
    if (keys.first > 0) {
      final double gap = keys.first / ticksPerQuarter;
      beats.add(GpBeat.rest(duration: gap));
      covered += gap;
    }

    for (int k = 0; k < keys.length; k++) {
      final int key = keys[k];
      final double pos = key / ticksPerQuarter;
      double dur = durationAt[key] ?? 0.25;
      if (k + 1 < keys.length) dur = keys[k + 1] / ticksPerQuarter - pos;
      if (dur <= 0.0001) continue;

      double finalDur = dur;
      if (swing != null && (dur - swing.unit).abs() < 0.01) {
        final double slot = pos / swing.unit;
        final bool onBeat = (slot.round() - slot).abs() < 0.02 && slot.round() % 2 == 0;
        finalDur = onBeat ? dur * swing.longRatio : dur * (2.0 - swing.longRatio);
      }

      final List<GpNote> notes = notesAt[key]!;
      final StrumDirection strum = strumAt[key] ?? StrumDirection.none;
      if (notes.isEmpty) {
        beats.add(GpBeat(
          notes: [GpNote.rest(duration: finalDur)],
          duration: finalDur,
          unswungDuration: dur,
        ));
      } else {
        beats.add(GpBeat(
          notes: [for (final GpNote n in notes) n.copyWith(duration: finalDur)],
          duration: finalDur,
          unswungDuration: dur,
          strumDirection: strum,
        ));
      }
      covered += dur;
    }

    if (covered < barQuarters - 0.001) {
      beats.add(GpBeat.rest(duration: barQuarters - covered));
    }
    return beats;
  }
}