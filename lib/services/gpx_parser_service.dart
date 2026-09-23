import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/gp_score.dart';
import '../models/gp_track.dart';

/// Parses Guitar Pro 7/8 (.gp) files into a [GpScore].
///
/// The .gp format is a ZIP archive containing a `score.gpif` (or `main.xml`)
/// GPIF XML document. All ZIP and XML handling lives here so that the UI layer
/// has no dependency on `archive` or `xml`.
class GpxParserService {
  GpxParserService._();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Reads bytes from [path] or [bytesData], then offloads the heavy ZIP
  /// decoding and XML parsing to a background [Isolate] to keep the UI thread
  /// responsive.
  ///
  /// Exactly one of [path] or [bytesData] must be non-null.
  ///
  /// Throws a descriptive [Exception] on format or parse errors.
  static Future<GpScore> parseGpFile(
    String? path,
    List<int>? bytesData,
  ) async {
    List<int> bytes;
    if (path != null) {
      bytes = await File(path).readAsBytes();
    } else if (bytesData != null) {
      bytes = bytesData;
    } else {
      throw Exception('Could not read file data.');
    }

    // Offload the heavy ZIP decoding and XML parsing to a background isolate.
    return Isolate.run(() => _processScoreData(bytes));
  }

  // ---------------------------------------------------------------------------
  // Isolate payload — no Flutter dependencies allowed here
  // ---------------------------------------------------------------------------

  /// Top-level-compatible static method that performs all CPU-intensive work
  /// (ZIP decode + XML parse) inside the background isolate spawned by
  /// [parseGpFile].
  static GpScore _processScoreData(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on FormatException {
      throw Exception(
        'Invalid GP format. Ensure you are using a Guitar Pro 7/8 (.gp) '
        'file, not an older .gpx or .gp5 file.',
      );
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
      throw Exception(
        'Invalid .gp file: Could not find score.gpif or main.xml inside the archive.',
      );
    }

    final String gpifContent =
        String.fromCharCodes(gpifFile.content as List<int>);
    final XmlDocument document = XmlDocument.parse(gpifContent);

    final String title =
        document.findAllElements('Title').firstOrNull?.innerText ??
            'Unknown Title';
    final String artist =
        document.findAllElements('Artist').firstOrNull?.innerText ??
            'Unknown Artist';

    // Derive notesPerMeasure from the time signature of the first MasterBar.
    int notesPerMeasure = 16;
    final String? firstTime = document
        .findAllElements('MasterBar')
        .firstOrNull
        ?.findElements('Time')
        .firstOrNull
        ?.innerText;
    if (firstTime != null) {
      final List<String> parts = firstTime.split('/');
      if (parts.length == 2) {
        final int? num = int.tryParse(parts[0]);
        if (num != null && num > 0) notesPerMeasure = num * 4;
      }
    }

    // Extract the first tempo automation value.
    int parsedTempo = 120;
    final tempoElem = document
        .findAllElements('Automation')
        .where(
          (e) => e.findElements('Type').firstOrNull?.innerText == 'Tempo',
        )
        .firstOrNull
        ?.findElements('Value')
        .firstOrNull
        ?.innerText;
    if (tempoElem != null) {
      final parts = tempoElem.split(' ');
      if (parts.isNotEmpty) {
        parsedTempo = int.tryParse(parts[0]) ?? 120;
      }
    }

    final List<GpTrack> tracks = _parseTracksFromDocument(document);

    return GpScore(
      title: title,
      artist: artist,
      tempo: parsedTempo,
      notesPerMeasure: notesPerMeasure,
      tracks: tracks,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static List<GpTrack> _parseTracksFromDocument(XmlDocument document) {
    final List<XmlElement> trackElements =
        document.findAllElements('Track').toList();
    final List<String> trackNames = trackElements
        .map(
          (t) =>
              t.findElements('Name').firstOrNull?.innerText.trim() ?? 'Track',
        )
        .toList();

    if (trackNames.isEmpty) trackNames.add('All Tracks');

    // Build rhythm-duration lookup table.
    final Map<String, double> rhythmMap = {};
    final Map<String, bool> rhythmIs8th = {};
    final rhythmsElement = document.findAllElements('Rhythms').firstOrNull;

    if (rhythmsElement != null) {
      for (final rhythm in rhythmsElement.findAllElements('Rhythm')) {
        final id = rhythm.getAttribute('id') ?? '';
        final noteVal =
            rhythm.findElements('NoteValue').firstOrNull?.innerText ?? 'Quarter';

        double val = 1.0;
        switch (noteVal) {
          case 'Whole':
            val = 4.0;
            break;
          case 'Half':
            val = 2.0;
            break;
          case 'Quarter':
            val = 1.0;
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
          default:
            val = 1.0;
        }

        final dot = rhythm
            .findElements('AugmentationDot')
            .firstOrNull
            ?.getAttribute('count');
        final bool hasDot = dot != null && dot.isNotEmpty;
        if (dot == '1') val *= 1.5;
        if (dot == '2') val *= 1.75;

        final tuplet = rhythm.findElements('PrimaryTuplet').firstOrNull;
        final bool hasTuplet = tuplet != null;
        if (tuplet != null) {
          final numStr = tuplet.getAttribute('num') ?? '3';
          final denStr = tuplet.getAttribute('den') ?? '2';
          val *= (int.parse(denStr) / int.parse(numStr));
        }

        rhythmMap[id] = val;
        rhythmIs8th[id] =
            (noteVal == '8th' || noteVal == 'Eighth') && !hasDot && !hasTuplet;
      }
    }

    // Build note-id → [string, fret] lookup.
    final Map<String, List<int>> noteIdToNote = {};
    for (final XmlElement note in document.findAllElements('Note')) {
      final String id = note.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final XmlElement? strNode =
          note.findAllElements('String').firstOrNull ??
              note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode =
          note.findAllElements('Fret').firstOrNull ??
              note.findAllElements('FretNum').firstOrNull;
      if (strNode == null || fretNode == null) continue;

      final int? stringNum = int.tryParse(strNode.innerText.trim());
      final int? fretNum = int.tryParse(fretNode.innerText.trim());
      if (stringNum == null || fretNum == null) continue;

      final int displayString = stringNum + 1;
      if (displayString >= 1 && displayString <= 8) {
        noteIdToNote[id] = [displayString, fretNum];
      }
    }

    // Build beat-id → beat-data lookup.
    final Map<String, dynamic> beatIdToBeat = {};
    for (final XmlElement beat in document.findAllElements('Beat')) {
      final String id = beat.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final String rhythmRef =
          beat.findElements('Rhythm').firstOrNull?.getAttribute('ref') ?? '';
      final double beatDuration = rhythmMap[rhythmRef] ?? 1.0;
      final bool is8th = rhythmIs8th[rhythmRef] ?? false;

      final String notesText =
          beat.findElements('Notes').firstOrNull?.innerText ?? '';
      final List<List<int>> notes = notesText
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty && noteIdToNote.containsKey(s))
          .map((nid) => noteIdToNote[nid]!)
          .toList();

      if (notes.isEmpty) {
        notes.add([-1, -1]); // Rest
      }

      beatIdToBeat[id] = {
        'notes': notes,
        'rhythm': beatDuration,
        'is8th': is8th,
      };
    }

    // Build voice-id → beats lookup.
    final Map<String, List<dynamic>> voiceIdToBeats = {};
    for (final XmlElement voice in document.findAllElements('Voice')) {
      final String id = voice.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final String beatsText =
          voice.findElements('Beats').firstOrNull?.innerText ?? '';
      final List<dynamic> beats = [];
      for (final String bid
          in beatsText.trim().split(' ').where((s) => s.isNotEmpty)) {
        if (beatIdToBeat.containsKey(bid)) {
          beats.add(beatIdToBeat[bid]);
        }
      }
      voiceIdToBeats[id] = beats;
    }

    // Build bar-id → beats + shuffle flag lookup.
    final Map<String, List<dynamic>> barIdToBeats = {};
    final Map<String, bool> barShuffleMap = {};
    for (final XmlElement bar in document.findAllElements('Bar')) {
      final String id = bar.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      final String tf =
          bar.findElements('TripletFeel').firstOrNull?.innerText.toLowerCase() ??
              '';
      final String sh =
          bar.findElements('Shuffle').firstOrNull?.innerText.toLowerCase() ?? '';
      if (tf.contains('8th') ||
          tf.contains('triplet') ||
          tf.contains('shuffle') ||
          sh.isNotEmpty) {
        barShuffleMap[id] = true;
      }

      final String voicesText =
          bar.findElements('Voices').firstOrNull?.innerText ?? '';
      final List<String> voiceIds =
          voicesText.trim().split(' ').where((s) => s.isNotEmpty).toList();
      barIdToBeats[id] =
          voiceIds.isNotEmpty ? (voiceIdToBeats[voiceIds[0]] ?? []) : [];
    }

    // Accumulate per-track notes and rhythms by iterating MasterBars.
    final List<List<List<int>>> trackNotes =
        List.generate(trackNames.length, (_) => []);
    final List<List<double>> trackRhythms =
        List.generate(trackNames.length, (_) => []);

    for (final XmlElement masterBar in document.findAllElements('MasterBar')) {
      final String tf = masterBar
              .findElements('TripletFeel')
              .firstOrNull
              ?.innerText
              .toLowerCase() ??
          '';
      final String sh = masterBar
              .findElements('Shuffle')
              .firstOrNull
              ?.innerText
              .toLowerCase() ??
          '';
      final bool masterBarShuffle = tf.contains('8th') ||
          tf.contains('triplet') ||
          tf.contains('shuffle') ||
          sh.isNotEmpty;

      final String barsText =
          masterBar.findElements('Bars').firstOrNull?.innerText ?? '';
      final List<String> barIds =
          barsText.trim().split(' ').where((s) => s.isNotEmpty).toList();

      for (int i = 0; i < barIds.length && i < trackNotes.length; i++) {
        final String barId = barIds[i];
        final bool isShuffle =
            masterBarShuffle || (barShuffleMap[barId] == true);
        final List<dynamic> barBeats = barIdToBeats[barId] ?? [];

        int eighthIndexInBar = 0;
        for (final beat in barBeats) {
          final List<List<int>> beatNotes = beat['notes'];
          double rhythm = beat['rhythm'];
          final bool is8th = beat['is8th'] == true;

          if (isShuffle && is8th) {
            if (eighthIndexInBar % 2 == 0) {
              rhythm = 0.5 * (4.0 / 3.0);
            } else {
              rhythm = 0.5 * (2.0 / 3.0);
            }
            eighthIndexInBar++;
          } else if (!is8th) {
            eighthIndexInBar += (rhythm / 0.5).round();
          }

          for (int n = 0; n < beatNotes.length; n++) {
            trackNotes[i].add(beatNotes[n]);
            trackRhythms[i].add(n == beatNotes.length - 1 ? rhythm : 0.0);
          }
        }
      }
    }

    if (trackNotes.any((t) => t.isNotEmpty)) {
      return [
        for (int i = 0; i < trackNames.length; i++)
          GpTrack(
            id: '$i',
            name: trackNames[i],
            notes: trackNotes[i],
            rhythms: trackRhythms[i],
          ),
      ];
    }

    // Fallback: flat note list when structured parsing yields nothing.
    final List<List<int>> flatNotes = [];
    final List<double> flatRhythms = [];
    for (final XmlElement note in document.findAllElements('Note')) {
      final XmlElement? strNode =
          note.findAllElements('String').firstOrNull ??
              note.findAllElements('Str').firstOrNull;
      final XmlElement? fretNode =
          note.findAllElements('Fret').firstOrNull ??
              note.findAllElements('FretNum').firstOrNull;
      if (strNode == null || fretNode == null) continue;

      final int? stringNum = int.tryParse(strNode.innerText.trim());
      final int? fretNum = int.tryParse(fretNode.innerText.trim());
      if (stringNum == null || fretNum == null) continue;

      final int displayString = stringNum + 1;
      if (displayString >= 1 && displayString <= 8) {
        flatNotes.add([displayString, fretNum]);
        flatRhythms.add(0.25);
      }
    }

    return [
      GpTrack(id: '0', name: 'All Tracks', notes: flatNotes, rhythms: flatRhythms),
    ];
  }
}

