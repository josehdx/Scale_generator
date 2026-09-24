import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/gp_score.dart';
import '../models/gp_track.dart';
import '../models/master_bar_event.dart';

class GpxParserService {
  GpxParserService._();

  static const Map<int, int> _standardTuning = {
    1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40, 7: 35, 8: 30,
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
      throw Exception('Could not read file data. File may have been deleted.');
    }
    
    return Isolate.run(() => _processScoreData({'fileName': fileName, 'filePath': path ?? '', 'bytes': bytes}));
  }

  static GpScore _processScoreData(Map<String, dynamic> args) {
    final String fileName = args['fileName'];
    final String filePath = args['filePath'];
    final List<int> bytes = args['bytes'];
    final Archive archive;

    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on FormatException {
      throw Exception('Invalid GP format. Ensure you are using a Guitar Pro 7/8 (.gp) file.');
    }

    ArchiveFile? gpifFile;
    for (final file in archive) {
      final String baseName = file.name.split('/').last.toLowerCase();
      if (baseName == 'score.gpif' || baseName == 'main.xml') {
        gpifFile = file;
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
    final firstGlobalTempo = document.findAllElements('Automation')
        .where((e) => e.findElements('Type').firstOrNull?.innerText == 'Tempo')
        .firstOrNull?.findElements('Value').firstOrNull?.innerText;
        
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

    final List<GpTrack> tracks = _parseTracksFromDocument(document);

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

      final localTempoVal = mb.findAllElements('Automation')
          .where((e) => e.findElements('Type').firstOrNull?.innerText == 'Tempo')
          .firstOrNull?.findElements('Value').firstOrNull?.innerText;
          
      if (localTempoVal != null && localTempoVal.isNotEmpty) {
        final parts = localTempoVal.split(' ');
        final t = int.tryParse(parts[0]);
        if (t != null && t > 0) currentTempo = t;
      } else if (barIndexToTempo.containsKey(i)) {
        currentTempo = barIndexToTempo[i]!;
      }

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
      ));

      cumulativeTick += ticks;
      cumulativeMs += durationMs;
    }
    return events;
  }

  static List<GpTrack> _parseTracksFromDocument(XmlDocument document) {
    final List<XmlElement> trackElements = document.findAllElements('Track').toList();
    final List<String> trackNames = trackElements.map((t) => t.findElements('Name').firstOrNull?.innerText.trim() ?? 'Track').toList();
    if (trackNames.isEmpty) trackNames.add('All Tracks');

    final Map<String, double> rhythmMap = {};
    final Map<String, bool> rhythmIs8th = {};
    final Map<String, bool> rhythmIs16th = {};
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
        final bool hasTuplet = tuplet != null;
        if (hasTuplet) {
          final numVal = int.tryParse(tuplet.getAttribute('num') ?? '3') ?? 3;
          final denVal = int.tryParse(tuplet.getAttribute('den') ?? '2') ?? 2;
          val *= (denVal / numVal);
        }

        rhythmMap[id] = val;
        rhythmIs8th[id] = (noteVal == '8th' || noteVal == 'Eighth') && dotCount == 0 && !hasTuplet;
        rhythmIs16th[id] = noteVal == '16th' && dotCount == 0 && !hasTuplet;
      }
    }

    final Map<String, GpNote> noteIdToNote = {};
    
    for (final XmlElement note in document.findAllElements('Note')) {
      final String id = note.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final XmlElement? strNode = note.findAllElements('String').firstOrNull ?? note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode = note.findAllElements('Fret').firstOrNull ?? note.findAllElements('FretNum').firstOrNull;
      
      if (strNode == null || fretNode == null) continue;
      
      final int? stringNum = int.tryParse(strNode.innerText.trim());
      final int? fretNum = int.tryParse(fretNode.innerText.trim());
      
      if (stringNum == null || fretNum == null) continue;
      final int displayString = 6 - stringNum;
      if (displayString < 1 || displayString > 8) continue;
      
      final int pitch = (_standardTuning[displayString] ?? 40) + fretNum;

      // Extract Performance Flags
      bool isTie = note.findAllElements('Tie').isNotEmpty;
      bool isLetRing = note.findAllElements('LetRing').isNotEmpty;
      bool isMuted = note.findAllElements('Muted').isNotEmpty || note.findAllElements('Mute').isNotEmpty || note.findAllElements('Dead').isNotEmpty;
      bool isPalmMute = note.findAllElements('PalmMute').isNotEmpty || note.findAllElements('PalmMuted').isNotEmpty;
      bool isLegato = note.findAllElements('Legato').isNotEmpty || note.findAllElements('Hopo').isNotEmpty || note.findAllElements('Hammer').isNotEmpty || note.findAllElements('Pull').isNotEmpty;
      bool isTap = note.findAllElements('Tap').isNotEmpty || note.findAllElements('Tapped').isNotEmpty;

      final ghostText = note.findAllElements('Ghost').firstOrNull?.innerText.toLowerCase();
      bool isGhost = (ghostText == '1' || ghostText == 'true');
      
      HarmonicType harmonicType = HarmonicType.none;
      final harmonicNode = note.findAllElements('Harmonic').firstOrNull;
      if (harmonicNode != null) {
        final typeText = (harmonicNode.getAttribute('type') ?? harmonicNode.getAttribute('flags') ?? '').toLowerCase();
        if (typeText.contains('artificial')) {
          harmonicType = HarmonicType.artificial;
        } else if (typeText.contains('pinch')) {
          harmonicType = HarmonicType.pinch;
        } else {
          harmonicType = HarmonicType.natural;
        }
      }

      for (final prop in note.findAllElements('Property')) {
        final pName = (prop.getAttribute('name') ?? '').toLowerCase();
        if (pName == 'muted' || pName == 'mute' || pName == 'dead') isMuted = true;
        else if (pName == 'palmmute' || pName == 'palm mute') isPalmMute = true;
        else if (pName == 'legato' || pName == 'hopo') isLegato = true;
        else if (pName == 'tie') isTie = true;
        else if (pName.contains('letring')) isLetRing = true;
        else if (pName == 'ghost') isGhost = true;
        else if (pName == 'tap' || pName == 'tapping') isTap = true;
      }

      // Advanced Multi-Schema Slide Extraction
      SlideType slideType = SlideType.none;
      final slideNode = note.findAllElements('Slide').firstOrNull;
      if (slideNode != null) {
        final sVal = (slideNode.getAttribute('type') ?? slideNode.getAttribute('flags') ?? slideNode.getAttribute('kind') ?? slideNode.innerText).toLowerCase();
        final int flags = int.tryParse(sVal) ?? 0;
        if (sVal.contains('below') || sVal.contains('into_from_below') || (flags & 16 != 0)) {
          slideType = SlideType.intoFromBelow;
        } else if (sVal.contains('above') || sVal.contains('into_from_above') || (flags & 32 != 0)) {
          slideType = SlideType.intoFromAbove;
        } else if (sVal.contains('down') || sVal.contains('out_down') || (flags & 4 != 0)) {
          slideType = SlideType.outDownwards;
        } else if (sVal.contains('up') || sVal.contains('out_up') || (flags & 8 != 0)) {
          slideType = SlideType.outUpwards;
        } else if (sVal.contains('shift') || (flags & 1 != 0)) {
          slideType = SlideType.shift;
        } else {
          slideType = SlideType.legato;
        }
      }
      
      if (slideType == SlideType.none) {
        for (final prop in note.findAllElements('Property')) {
          final pName = (prop.getAttribute('name') ?? '').toLowerCase();
          if (pName.contains('slide')) {
            slideType = SlideType.shift;
            break;
          }
        }
      }

      // --- Universal Bend Extraction ---
      GpBend? bend;
      final List<({double pos, double val})> rawPoints = [];
      
      // GPX / GP7 points are either <Point> or <BendPoint> globally within the note
      final pointNodes = [
        ...note.findAllElements('Point'),
        ...note.findAllElements('BendPoint')
      ];
      
      for (final pt in pointNodes) {
        final posStr = pt.getAttribute('position') ?? pt.getAttribute('pos') ?? pt.getAttribute('token') ?? pt.findElements('Position').firstOrNull?.innerText;
        final offStr = pt.getAttribute('offset') ?? pt.getAttribute('value') ?? pt.getAttribute('val') ?? pt.findElements('Offset').firstOrNull?.innerText ?? pt.findElements('Value').firstOrNull?.innerText;
        
        if (posStr != null && offStr != null) {
          rawPoints.add((
            pos: double.tryParse(posStr) ?? 0.0,
            val: double.tryParse(offStr) ?? 0.0,
          ));
        }
      }

      if (rawPoints.isNotEmpty) {
        double maxPos = rawPoints.map((e) => e.pos).reduce(max);
        double posDenominator = maxPos > 12.0 ? maxPos : (maxPos <= 1.0 && maxPos > 0.0 ? 1.0 : 12.0);
        double maxVal = rawPoints.map((e) => e.val).reduce(max);
        
        // GPIF XML: 50 units = 1 semitone, 100 units = 2 semitones
        double valDenominator = (maxVal <= 12.0 && maxVal > 0.0) ? 4.0 : 50.0;

        final List<BendPoint> points = [];
        double maxOffsetSemitones = 0.0;
        for (final raw in rawPoints) {
          final double normalizedPos = (raw.pos / posDenominator).clamp(0.0, 1.0);
          final double offsetSemitones = raw.val / valDenominator;
          if (offsetSemitones > maxOffsetSemitones) maxOffsetSemitones = offsetSemitones;
          points.add(BendPoint(position: normalizedPos, offset: offsetSemitones));
        }
        points.sort((a, b) => a.position.compareTo(b.position));
        bend = GpBend(maximumPitchOffset: maxOffsetSemitones, envelope: points);
      } else {
        // Fallback for flat Property tags
        for (final prop in note.findAllElements('Property')) {
          final pName = (prop.getAttribute('name') ?? '').toLowerCase();
          if (pName.contains('bend')) {
            final floatVal = double.tryParse(prop.findElements('Float').firstOrNull?.innerText ?? prop.innerText.trim());
            if (floatVal != null && floatVal > 0) {
              double semitones = floatVal > 12.0 ? floatVal / 50.0 : floatVal;
              bend = GpBend(
                maximumPitchOffset: semitones,
                envelope: [
                  const BendPoint(position: 0.0, offset: 0.0),
                  BendPoint(position: 0.5, offset: semitones),
                  BendPoint(position: 1.0, offset: semitones),
                ],
              );
              break;
            }
            final strVal = prop.findElements('String').firstOrNull?.innerText.toLowerCase() ?? prop.innerText.trim().toLowerCase();
            if (strVal.isNotEmpty) {
              double semitones = 0.0;
              if (strVal.contains('half')) semitones = 1.0;
              else if (strVal.contains('full') || strVal == '1') semitones = 2.0;
              else if (strVal.contains('1.5')) semitones = 3.0;
              else if (strVal.contains('2')) semitones = 4.0;
              
              if (semitones > 0) {
                 bend = GpBend(
                    maximumPitchOffset: semitones,
                    envelope: [
                      const BendPoint(position: 0.0, offset: 0.0),
                      BendPoint(position: 0.5, offset: semitones),
                      BendPoint(position: 1.0, offset: semitones),
                    ],
                  );
                  break;
              }
            }
          }
        }
      }

      GpVibrato? vibrato;
      final vibNode = note.findAllElements('Vibrato').firstOrNull;
      final hasVibProp = note.findAllElements('Property').any((p) => (p.getAttribute('name') ?? '').toLowerCase() == 'vibrato');
      if (vibNode != null || hasVibProp) vibrato = const GpVibrato();

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

    final Map<String, dynamic> beatIdToBeat = {};
    for (final XmlElement beat in document.findAllElements('Beat')) {
      final String id = beat.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      
      final String rhythmRef = beat.findElements('Rhythm').firstOrNull?.getAttribute('ref') ?? '';
      final double beatDuration = rhythmMap[rhythmRef] ?? 1.0;
      final bool is8th = rhythmIs8th[rhythmRef] ?? false;
      final bool is16th = rhythmIs16th[rhythmRef] ?? false;
      final String notesText = beat.findElements('Notes').firstOrNull?.innerText ?? '';
      
      StrumDirection strumDir = StrumDirection.none;
      final strumNode = beat.findElements('Strum').firstOrNull;
      if (strumNode != null) {
        final dir = (strumNode.getAttribute('direction') ?? strumNode.innerText).toLowerCase();
        if (dir.contains('down')) strumDir = StrumDirection.down;
        else if (dir.contains('up')) strumDir = StrumDirection.up;
      }
      for (final prop in beat.findElements('Property')) {
        final pName = (prop.getAttribute('name') ?? '').toLowerCase();
        if (pName.contains('strum')) {
          final sVal = prop.innerText.toLowerCase();
          if (sVal.contains('down')) strumDir = StrumDirection.down;
          else if (sVal.contains('up')) strumDir = StrumDirection.up;
        }
      }

      final List<GpNote> notes = notesText.trim().split(' ')
          .where((s) => s.isNotEmpty && noteIdToNote.containsKey(s))
          .map((nid) => noteIdToNote[nid]!).toList();
          
      if (notes.isEmpty) notes.add(GpNote.rest(duration: beatDuration));
      
      beatIdToBeat[id] = {
        'notes': notes, 
        'rhythm': beatDuration, 
        'is8th': is8th, 
        'is16th': is16th,
        'strumDirection': strumDir,
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

    final Map<String, List<dynamic>> barIdToBeats = {};
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
      barIdToBeats[id] = voiceIds.isNotEmpty ? (voiceIdToBeats[voiceIds[0]] ?? []) : [];
    }

    final List<List<GpBeat>> trackBeats = List.generate(trackNames.length, (_) => []);
    final List<List<int>> trackMeasureEnds = List.generate(trackNames.length, (_) => []);
    
    for (final XmlElement masterBar in document.findAllElements('MasterBar')) {
      final String tf = masterBar.findElements('TripletFeel').firstOrNull?.innerText.toLowerCase() ?? '';
      final String sh = masterBar.findElements('Shuffle').firstOrNull?.innerText.toLowerCase() ?? '';
      final bool shuffle8th = tf.contains('8th') || sh.isNotEmpty;
      final bool shuffle16th = tf.contains('16th');
      
      final String barsText = masterBar.findElements('Bars').firstOrNull?.innerText ?? '';
      final List<String> barIds = barsText.trim().split(' ').where((s) => s.isNotEmpty).toList();
      
      for (int i = 0; i < barIds.length && i < trackBeats.length; i++) {
        final String barId = barIds[i];
        final bool isBarShuffle8th = shuffle8th || (barShuffleMap[barId] == true);
        final List<dynamic> barBeats = barIdToBeats[barId] ?? [];
        
        double measurePositionQuarters = 0.0;
        for (final beat in barBeats) {
          final List<GpNote> beatNotes = beat['notes'];
          double baseRhythm = beat['rhythm'];
          final bool is8th = beat['is8th'] == true;
          final bool is16th = beat['is16th'] == true;
          final StrumDirection strumDir = beat['strumDirection'] ?? StrumDirection.none;
          
          double finalRhythm = baseRhythm;
          if (isBarShuffle8th && is8th) {
            final int eighthIndex = (measurePositionQuarters / 0.5).round();
            if (eighthIndex % 2 == 0) finalRhythm = 0.5 * (4.0 / 3.0);
            else finalRhythm = 0.5 * (2.0 / 3.0);
          } else if (shuffle16th && is16th) {
            final int sixteenthIndex = (measurePositionQuarters / 0.25).round();
            if (sixteenthIndex % 2 == 0) finalRhythm = 0.25 * (4.0 / 3.0);
            else finalRhythm = 0.25 * (2.0 / 3.0);
          }
          measurePositionQuarters += baseRhythm;
          
          final List<GpNote> notesWithDuration = beatNotes.map((orig) => GpNote(
            stringNum: orig.stringNum, fretNum: orig.fretNum, pitch: orig.pitch, duration: finalRhythm,
            isTie: orig.isTie, isLetRing: orig.isLetRing, isMuted: orig.isMuted, isPalmMute: orig.isPalmMute,
            isLegato: orig.isLegato, isGhost: orig.isGhost, isTap: orig.isTap, harmonicType: orig.harmonicType,
            slideType: orig.slideType, bend: orig.bend, vibrato: orig.vibrato,
          )).toList();
          
          trackBeats[i].add(GpBeat(
            notes: notesWithDuration, 
            duration: finalRhythm,
            strumDirection: strumDir,
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
          GpTrack(id: '$i', name: trackNames[i], beats: trackBeats[i], measureEndIndices: trackMeasureEnds[i]),
      ];
    }
    return [GpTrack(id: '0', name: 'Empty', beats: [])];
  }
}