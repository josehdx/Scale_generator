import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/gp_score.dart';
import '../models/gp_track.dart';
import '../models/master_bar_event.dart';

class GpxParserService {
  GpxParserService._();

  static const Map<int, int> _standardTuning = {
    1: 64, // High E
    2: 59, // B
    3: 55, // G
    4: 50, // D
    5: 45, // A
    6: 40, // Low E
    7: 35, // Low B (7-string)
    8: 30, // Low F# (8-string)
  };

  static Future<GpScore?> pickAndParse() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.gp') && !file.name.toLowerCase().endsWith('.gpx')) {
      throw Exception('Invalid file type. Please select a .gp or .gpx file.');
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final persistentPath = '${docsDir.path}/${file.name}';
    final persistentFile = File(persistentPath);
    if (file.bytes != null) {
      await persistentFile.writeAsBytes(file.bytes!);
    } else if (file.path != null) {
      await File(file.path!).copy(persistentPath);
    }
    return await parseGpFile(file.name, persistentPath, file.bytes);
  }

  static Future<GpScore> parseGpFile(String fileName, String? path, List<int>? bytesData) async {
    List<int> bytes;
    if (path != null && await File(path).exists()) {
      bytes = await File(path).readAsBytes();
    } else if (bytesData != null) {
      bytes = bytesData;
    } else {
      throw Exception('Could not read file data.');
    }
    return Isolate.run(() => _processScoreData({
          'fileName': fileName,
          'filePath': path ?? '',
          'bytes': bytes,
        }));
  }

  static GpScore _processScoreData(Map<String, dynamic> args) {
    final String fileName = args['fileName'];
    final String filePath = args['filePath'];
    final List<int> bytes = args['bytes'];
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on FormatException {
      throw Exception('Invalid GP format. Ensure you are using a Guitar Pro (.gp/.gpx) file.');
    }
    ArchiveFile? gpifFile;
    bool isGpx = false;
    for (final file in archive) {
      final String baseName = file.name.split('/').last.toLowerCase();
      if (baseName == 'score.gpif') {
        gpifFile = file;
        isGpx = true;
        break;
      } else if (baseName == 'main.xml') {
        gpifFile = file;
        isGpx = false;
        break;
      }
    }
    if (gpifFile == null) {
      throw Exception('Invalid .gp file: Could not find score.gpif or main.xml.');
    }
    final String gpifContent = String.fromCharCodes(gpifFile.content as List<int>);
    final XmlDocument document = XmlDocument.parse(gpifContent);
    final String title = document.findAllElements('Title').firstOrNull?.innerText ?? 'Unknown Title';
    final String artist = document.findAllElements('Artist').firstOrNull?.innerText ?? 'Unknown Artist';
    int initialTempo = 120;
    final firstGlobalTempo = document
        .findAllElements('Automation')
        .where((e) => e.findElements('Type').firstOrNull?.innerText == 'Tempo')
        .firstOrNull
        ?.findElements('Value')
        .firstOrNull
        ?.innerText;
    if (firstGlobalTempo != null) {
      final parts = firstGlobalTempo.split(' ');
      if (parts.isNotEmpty) initialTempo = int.tryParse(parts[0]) ?? 120;
    }
    final List<MasterBarEvent> masterBars = _parseMasterBars(document, initialTempo);
    int initialNotesPerMeasure = 16;
    if (masterBars.isNotEmpty) {
      initialNotesPerMeasure = masterBars.first.sixteenthCount;
      if (initialNotesPerMeasure <= 0) initialNotesPerMeasure = 16;
    }
    final List<GpTrack> tracks = _parseTracksFromDocument(document, isGpx);
    return GpScore(
      fileName: fileName,
      filePath: filePath,
      title: title,
      artist: artist,
      tempo: masterBars.isNotEmpty ? masterBars.first.tempo : initialTempo,
      notesPerMeasure: initialNotesPerMeasure,
      masterBars: masterBars,
      tracks: tracks,
    );
  }

  static List<MasterBarEvent> _parseMasterBars(XmlDocument document, int initialTempo) {
    final List<XmlElement> masterBarNodes = document.findAllElements('MasterBar').toList();
    final Map<int, int> barIndexToTempo = {};
    for (final automation in document.findAllElements('Automation')) {
      final type = automation.findElements('Type').firstOrNull?.innerText;
      if (type == 'Tempo') {
        final valText = automation.findElements('Value').firstOrNull?.innerText ?? '';
        final barText = automation.findElements('Bar').firstOrNull?.innerText ?? '';
        final parts = valText.split(' ');
        final tVal = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
        final bIdx = int.tryParse(barText);
        if (tVal != null && bIdx != null) barIndexToTempo[bIdx] = tVal;
      }
    }
    final List<MasterBarEvent> events = [];
    int currentTempo = initialTempo;
    int currentNumerator = 4;
    int currentDenominator = 4;
    int cumulativeTick = 0;
    double cumulativeMs = 0.0;
    for (int i = 0; i < masterBarNodes.length; i++) {
      final mb = masterBarNodes[i];
      final String? timeText = mb.findElements('Time').firstOrNull?.innerText.trim();
      
      if (timeText != null && timeText.contains('/')) {
        final parts = timeText.split('/');
        final n = int.tryParse(parts[0]);
        final d = int.tryParse(parts[1]);
        if (n != null && n > 0 && d != null && d > 0) {
          currentNumerator = n;
          currentDenominator = d;
        }
      }
      final localTempoVal = mb
          .findAllElements('Automation')
          .where((e) => e.findElements('Type').firstOrNull?.innerText == 'Tempo')
          .firstOrNull
          ?.findElements('Value')
          .firstOrNull
          ?.innerText;
      if (localTempoVal != null && localTempoVal.isNotEmpty) {
        final parts = localTempoVal.split(' ');
        final t = int.tryParse(parts[0]);
        if (t != null && t > 0) currentTempo = t;
      } else if (barIndexToTempo.containsKey(i)) {
        currentTempo = barIndexToTempo[i]!;
      }
      final String tf = mb.findElements('TripletFeel').firstOrNull?.innerText ?? '';
      
      final double quarters = currentNumerator * (4.0 / currentDenominator);
      final int ticks = (quarters * 960).round();
      final double durationMs = quarters * (60000.0 / currentTempo);
      events.add(MasterBarEvent(
        barIndex: i,
        tempo: currentTempo,
        numerator: currentNumerator,
        denominator: currentDenominator,
        startTick: cumulativeTick,
        startMs: cumulativeMs,
        durationMs: durationMs,
        tripletFeel: tf,
      ));
      cumulativeTick += ticks;
      cumulativeMs += durationMs;
    }
    return events;
  }

  static bool _hasPropertyOrNode(XmlElement note, List<String> names) {
    if (names.any((name) => note.findAllElements(name).isNotEmpty)) return true;
    final props = note.findAllElements('Property');
    for (final prop in props) {
      final propName = prop.getAttribute('name');
      if (propName != null && names.contains(propName)) return true;
    }
    return false;
  }

  static List<GpTrack> _parseTracksFromDocument(XmlDocument document, bool isGpx) {
    final List<XmlElement> trackElements = document.findAllElements('Track').toList();
    final List<String> trackNames = [];
    final List<bool> trackIsPercussion = [];
    for (final t in trackElements) {
      final name = t.findElements('Name').firstOrNull?.innerText.trim() ?? 'Track';
      final isPerc = t.findElements('IsPercussion').firstOrNull?.innerText.toLowerCase() == 'true' ||
          t.findElements('GeneralMidi').firstOrNull?.findElements('PrimaryChannel').firstOrNull?.innerText == '9';
      trackNames.add(name);
      trackIsPercussion.add(isPerc);
    }
    if (trackNames.isEmpty) {
      trackNames.add('All Tracks');
      trackIsPercussion.add(false);
    }
    final Map<String, double> rhythmMap = {};
    final rhythmsElement = document.findAllElements('Rhythms').firstOrNull;
    if (rhythmsElement != null) {
      for (final rhythm in rhythmsElement.findAllElements('Rhythm')) {
        final id = rhythm.getAttribute('id') ?? '';
        final noteVal = rhythm.findElements('NoteValue').firstOrNull?.innerText ?? 'Quarter';
        
        double val = 1.0;
        switch (noteVal) {
          case 'Whole': val = 4.0; break;
          case 'Half': val = 2.0; break;
          case 'Quarter': val = 1.0; break;
          case '8th': case 'Eighth': val = 0.5; break;
          case '16th': val = 0.25; break;
          case '32nd': val = 0.125; break;
          case '64th': val = 0.0625; break;
          default: val = 1.0;
        }
        final dotCount = int.tryParse(rhythm.findElements('AugmentationDot').firstOrNull?.getAttribute('count') ?? '0') ?? 0;
        if (dotCount == 1) val *= 1.5;
        else if (dotCount == 2) val *= 1.75;
        final tuplet = rhythm.findElements('PrimaryTuplet').firstOrNull;
        if (tuplet != null) {
          final numVal = int.tryParse(tuplet.getAttribute('num') ?? '3') ?? 3;
          final denVal = int.tryParse(tuplet.getAttribute('den') ?? '2') ?? 2;
          val *= (denVal / numVal);
        }
        rhythmMap[id] = val;
      }
    }
    final Map<String, GpNote> noteIdToNote = {};
    int parsedBendCount = 0;

    for (final XmlElement note in document.findAllElements('Note')) {
      final String id = note.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final XmlElement? strNode = note.findAllElements('String').firstOrNull ?? note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode = note.findAllElements('Fret').firstOrNull ?? note.findAllElements('FretNum').firstOrNull;
      final XmlElement? midiNode = note.findAllElements('MidiNumber').firstOrNull ?? note.findAllElements('Pitch').firstOrNull;
      int displayString = 1;
      int fretNum = 0;
      int pitch = 60;
      if (strNode != null && fretNode != null) {
        final int? stringNum = int.tryParse(strNode.innerText.trim());
        final int? fNum = int.tryParse(fretNode.innerText.trim());
        if (stringNum != null && fNum != null) {
          displayString = (6 - stringNum).clamp(1, 8);
          fretNum = fNum;
          pitch = (_standardTuning[displayString] ?? 40) + fretNum;
        }
      } else if (midiNode != null) {
        pitch = int.tryParse(midiNode.innerText.trim()) ?? 60;
        displayString = -1;
        fretNum = pitch;
      }
      bool isTie = _hasPropertyOrNode(note, ['Tie', 'Tied']);
      bool isLetRing = _hasPropertyOrNode(note, ['LetRing']);
      bool isMuted = _hasPropertyOrNode(note, ['Muted', 'Mute', 'Dead']);
      bool isPalmMute = _hasPropertyOrNode(note, ['PalmMute', 'PalmMuted']);
      bool isLegato = _hasPropertyOrNode(note, ['Legato', 'Hopo']);
      bool isTap = _hasPropertyOrNode(note, ['Tap', 'Tapped', 'Tapping']);
      final ghostText = note.findAllElements('Ghost').firstOrNull?.innerText.toLowerCase();
      bool isGhost = (ghostText == '1' || ghostText == 'true') || _hasPropertyOrNode(note, ['Ghost']);
      HarmonicType harmonicType = HarmonicType.none;
      final harmonicNode = note.findAllElements('Harmonic').firstOrNull;
      if (harmonicNode != null) {
        final typeText = (harmonicNode.getAttribute('type') ?? harmonicNode.getAttribute('flags') ?? '').toLowerCase();
        if (typeText.contains('artificial')) harmonicType = HarmonicType.artificial;
        else if (typeText.contains('pinch')) harmonicType = HarmonicType.pinch;
        else harmonicType = HarmonicType.natural;
      }
      SlideType slideType = SlideType.none;
      final slideNode = note.findAllElements('Slide').firstOrNull;
      if (slideNode != null) {
        final sVal = (slideNode.getAttribute('type') ?? slideNode.getAttribute('flags') ?? '').toLowerCase();
        if (sVal.contains('below')) slideType = SlideType.intoFromBelow;
        else if (sVal.contains('above')) slideType = SlideType.intoFromAbove;
        else if (sVal.contains('down')) slideType = SlideType.outDownwards;
        else if (sVal.contains('up')) slideType = SlideType.outUpwards;
        else if (sVal.contains('shift')) slideType = SlideType.shift;
        else slideType = SlideType.legato;
      }

      GpBend? bend;
      final List<({double pos, double val})> rawPoints = [];

      // 1. Check for direct <Bend> element
      final XmlElement? directBend = note.findAllElements('Bend').firstOrNull;
      if (directBend != null) {
        final pointNodes = directBend.findAllElements('Point').isNotEmpty
            ? directBend.findAllElements('Point')
            : directBend.findAllElements('BendPoint');
            
        for (final pt in pointNodes) {
          final posStr = pt.getAttribute('position') ?? pt.getAttribute('pos') ?? pt.getAttribute('Position') ?? pt.getAttribute('Pos');
          final offStr = pt.getAttribute('offset') ?? pt.getAttribute('value') ?? pt.getAttribute('Offset') ?? pt.getAttribute('Value');
          if (posStr != null && offStr != null) {
            final double p = double.tryParse(posStr) ?? 0.0;
            final double v = double.tryParse(offStr) ?? 0.0;
            rawPoints.add((pos: p, val: v));
          }
        }
      }

      // 2. Check for GPIF XML (<Property name="BendOriginOffset">)
      if (rawPoints.isEmpty) {
        final Map<String, double> propFloats = {};
        bool hasBendedProp = false;
        for (final prop in note.findAllElements('Property')) {
          final pName = prop.getAttribute('name');
          if (pName != null) {
            if (pName == 'Bended') hasBendedProp = true;
            final flt = prop.findElements('Float').firstOrNull?.innerText.trim();
            if (flt != null) {
              final double? val = double.tryParse(flt);
              if (val != null) propFloats[pName] = val;
            }
          }
        }

        if (hasBendedProp || propFloats.keys.any((k) => k.contains('Bend'))) {
          if (propFloats.containsKey('BendOriginOffset') && propFloats.containsKey('BendOriginValue')) {
            rawPoints.add((pos: propFloats['BendOriginOffset']!, val: propFloats['BendOriginValue']!));
          }
          if (propFloats.containsKey('BendMiddleOffset1') && propFloats.containsKey('BendMiddleValue')) {
            rawPoints.add((pos: propFloats['BendMiddleOffset1']!, val: propFloats['BendMiddleValue']!));
          }
          if (propFloats.containsKey('BendDestinationOffset') && propFloats.containsKey('BendDestinationValue')) {
            rawPoints.add((pos: propFloats['BendDestinationOffset']!, val: propFloats['BendDestinationValue']!));
          }
        }
      }

      if (rawPoints.isNotEmpty) {
        final List<BendPoint> points = [];
        double maxOffsetSemitones = 0.0;
        
        rawPoints.sort((a, b) => a.pos.compareTo(b.pos));

        for (final raw in rawPoints) {
          final double normalizedPos = (raw.pos / 100.0).clamp(0.0, 1.0); 
          
          double offsetSemitones = raw.val;
          if (raw.val > 10.0) {
            offsetSemitones = raw.val / 50.0;
          } else {
            offsetSemitones = raw.val / 4.0;
          }

          if (offsetSemitones > maxOffsetSemitones) maxOffsetSemitones = offsetSemitones;
          
          points.add(BendPoint(position: normalizedPos, offset: offsetSemitones));
        }
        bend = GpBend(maximumPitchOffset: maxOffsetSemitones, envelope: points);
        parsedBendCount++;
        
        debugPrint('[PARSER BEND DEBUG] SUCCESS | Note s:$displayString f:$fretNum | maxOffset: ${bend.maximumPitchOffset} semitones | points: ${bend.envelope}');
      }

      GpVibrato? vibrato;
      if (note.findAllElements('Vibrato').isNotEmpty || _hasPropertyOrNode(note, ['Vibrato'])) {
        vibrato = const GpVibrato();
      }
      noteIdToNote[id] = GpNote(
        stringNum: displayString,
        fretNum: fretNum,
        pitch: pitch,
        duration: 0.25,
        isTie: isTie,
        isLetRing: isLetRing,
        isMuted: isMuted,
        isPalmMute: isPalmMute,
        isLegato: isLegato,
        isGhost: isGhost,
        isTap: isTap,
        harmonicType: harmonicType,
        slideType: slideType,
        bend: bend,
        vibrato: vibrato,
      );
    }

    debugPrint('[PARSER BEND DEBUG] Document parsing complete. Total notes with bends detected: $parsedBendCount');

    final Map<String, dynamic> beatIdToBeat = {};
    for (final XmlElement beat in document.findAllElements('Beat')) {
      final String id = beat.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final String rhythmRef = beat.findElements('Rhythm').firstOrNull?.getAttribute('ref') ?? '';
      final double beatDuration = rhythmMap[rhythmRef] ?? 1.0;
      final String notesText = beat.findElements('Notes').firstOrNull?.innerText ?? '';
      final List<GpNote> notes = notesText
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty && noteIdToNote.containsKey(s))
          .map((nid) => noteIdToNote[nid]!)
          .toList();
      if (notes.isEmpty) notes.add(GpNote.rest(duration: beatDuration));
      beatIdToBeat[id] = {
        'notes': notes,
        'rhythm': beatDuration,
      };
    }
    final Map<String, List<dynamic>> voiceIdToBeats = {};
    for (final XmlElement voice in document.findAllElements('Voice')) {
      final String id = voice.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final String beatsText = voice.findElements('Beats').firstOrNull?.innerText ?? '';
      final List<dynamic> beats = [];
      for (final String bid in beatsText.trim().split(' ').where((s) => s.isNotEmpty)) {
        if (beatIdToBeat.containsKey(bid)) beats.add(beatIdToBeat[bid]);
      }
      voiceIdToBeats[id] = beats;
    }
    final Map<String, List<GpBeat>> barIdToBeats = {};
    final Map<String, bool> barShuffleMap = {};
    for (final XmlElement bar in document.findAllElements('Bar')) {
      final String id = bar.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final String tf = bar.findElements('TripletFeel').firstOrNull?.innerText.toLowerCase() ?? '';
      final String sh = bar.findElements('Shuffle').firstOrNull?.innerText.toLowerCase() ?? '';
      
      if (tf.contains('8th') || tf.contains('triplet') || tf.contains('shuffle') || sh.isNotEmpty) {
        barShuffleMap[id] = true;
      }
      final String voicesText = bar.findElements('Voices').firstOrNull?.innerText ?? '';
      final List<String> voiceIds = voicesText.trim().split(' ').where((s) => s.isNotEmpty).toList();
      final Map<double, List<GpNote>> positionNotes = {};
      final Map<double, double> positionDurations = {};
      for (int vIdx = 0; vIdx < voiceIds.length; vIdx++) {
        final voiceId = voiceIds[vIdx];
        final List<dynamic> vBeats = voiceIdToBeats[voiceId] ?? [];
        double currentPos = 0.0;
        for (final beat in vBeats) {
          final List<GpNote> beatNotes = beat['notes'];
          final double beatDur = beat['rhythm'];
          final double keyPos = (currentPos * 10000).round() / 10000.0;
          positionNotes.putIfAbsent(keyPos, () => []);
          positionDurations.putIfAbsent(keyPos, () => beatDur);
          for (final n in beatNotes) {
            if (!n.isRest) positionNotes[keyPos]!.add(n);
          }
          currentPos += beatDur;
        }
      }
      final List<double> sortedPositions = positionNotes.keys.toList()..sort();
      final List<GpBeat> mergedBarBeats = [];
      for (int pIdx = 0; pIdx < sortedPositions.length; pIdx++) {
        final double pos = sortedPositions[pIdx];
        final List<GpNote> notesAtPos = positionNotes[pos]!;
        double dur = positionDurations[pos] ?? 0.25;
        if (pIdx < sortedPositions.length - 1) {
          dur = sortedPositions[pIdx + 1] - pos;
        }
        if (notesAtPos.isEmpty) {
          mergedBarBeats.add(GpBeat.rest(duration: dur));
        } else {
          mergedBarBeats.add(GpBeat(
            notes: notesAtPos,
            duration: dur,
            unswungDuration: dur,
          ));
        }
      }
      barIdToBeats[id] = mergedBarBeats;
    }
    final List<List<GpBeat>> trackBeats = List.generate(trackNames.length, (_) => []);
    final List<List<int>> trackMeasureEnds = List.generate(trackNames.length, (_) => []);
    for (final XmlElement masterBar in document.findAllElements('MasterBar')) {
      final String tf = masterBar.findElements('TripletFeel').firstOrNull?.innerText.toLowerCase() ?? '';
      final String sh = masterBar.findElements('Shuffle').firstOrNull?.innerText.toLowerCase() ?? '';
      
      final bool shuffle8th = tf.contains('8th') || tf.contains('triplet') || sh.isNotEmpty;
      final bool shuffle16th = tf.contains('16th');
      final String barsText = masterBar.findElements('Bars').firstOrNull?.innerText ?? '';
      final List<String> barIds = barsText.trim().split(' ').where((s) => s.isNotEmpty).toList();
      for (int i = 0; i < barIds.length && i < trackBeats.length; i++) {
        final String barId = barIds[i];
        final bool isBarShuffle8th = shuffle8th || (barShuffleMap[barId] == true);
        final List<GpBeat> barBeats = barIdToBeats[barId] ?? [];
        
        double measurePositionQuarters = 0.0;
        for (final beat in barBeats) {
          final List<GpNote> beatNotes = beat.notes;
          double baseRhythm = beat.duration;
          double finalRhythm = baseRhythm;
          if (isBarShuffle8th && (baseRhythm - 0.5).abs() < 0.01) {
            final int eighthIndex = (measurePositionQuarters / 0.5).round();
            if (eighthIndex % 2 == 0) {
              finalRhythm = 0.5 * (4.0 / 3.0); 
            } else {
              finalRhythm = 0.5 * (2.0 / 3.0); 
            }
          } else if (shuffle16th && (baseRhythm - 0.25).abs() < 0.01) {
            final int sixteenthIndex = (measurePositionQuarters / 0.25).round();
            if (sixteenthIndex % 2 == 0) {
              finalRhythm = 0.25 * (4.0 / 3.0);
            } else {
              finalRhythm = 0.25 * (2.0 / 3.0);
            }
          }
          measurePositionQuarters += baseRhythm;
          final List<GpNote> notesWithDuration = beatNotes
              .map((orig) => GpNote(
                    stringNum: orig.stringNum,
                    fretNum: orig.fretNum,
                    pitch: orig.pitch,
                    duration: finalRhythm,
                    isTie: orig.isTie,
                    isLetRing: orig.isLetRing,
                    isMuted: orig.isMuted,
                    isPalmMute: orig.isPalmMute,
                    isLegato: orig.isLegato,
                    isGhost: orig.isGhost,
                    isTap: orig.isTap,
                    harmonicType: orig.harmonicType,
                    slideType: orig.slideType,
                    bend: orig.bend,
                    vibrato: orig.vibrato,
                  ))
              .toList();
          trackBeats[i].add(GpBeat(
            notes: notesWithDuration,
            duration: finalRhythm,
            unswungDuration: baseRhythm,
            strumDirection: beat.strumDirection,
          ));
        }
        if (trackBeats[i].isNotEmpty) {
          trackMeasureEnds[i].add(trackBeats[i].length - 1);
        }
      }
    }
    if (trackBeats.any((t) => t.isNotEmpty)) {
      return [
        for (int i = 0; i < trackNames.length; i++)
          GpTrack(
            id: '$i',
            name: trackNames[i],
            beats: trackBeats[i],
            measureEndIndices: trackMeasureEnds[i],
          ),
      ];
    }
    return [GpTrack(id: '0', name: 'Empty Track', beats: [])];
  }
}