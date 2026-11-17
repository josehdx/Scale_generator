import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/services/gpx_parser_service.dart';
import 'package:tab_generator/utils/gp_timeline.dart';

// NOTE: replace `tab_generator` with the `name:` from your pubspec.yaml.
//
// Put your real sample files in test/fixtures/*.gp.
//   * invariants are asserted for every file;
//   * `<name>.golden.json` is compared when present;
//   * run `UPDATE_GOLDEN=1 flutter test test/golden_gp_files_test.dart`
//     to (re)write the goldens after you reviewed the output.

Map<String, dynamic> summarize(String name) {
  final bytes = File('test/fixtures/$name').readAsBytesSync();
  final score = GpxParserService.parseBytes(bytes, fileName: name);
  final grid = BarGrid(score.masterBars, score.playOrder);
  return {
    'bars': score.masterBars.length,
    'playOrderLength': score.playOrder.length,
    'totalMs': grid.totalMs.round(),
    'tracks': [
      for (final t in score.tracks)
        {
          'name': t.name,
          'strings': t.stringCount,
          'beats': t.beats.length,
          'notes': t.beats.fold<int>(0, (a, b) => a + b.notes.where((n) => !n.isRest).length),
          'minPitch': t.allNotes.where((n) => !n.isRest).fold<int>(127, (a, n) => n.pitch < a ? n.pitch : a),
          'maxPitch': t.allNotes.where((n) => !n.isRest).fold<int>(0, (a, n) => n.pitch > a ? n.pitch : a),
        }
    ],
  };
}

void main() {
  final dir = Directory('test/fixtures');
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.gp')).map((f) => f.uri.pathSegments.last).toList()..sort())
      : <String>[];

  if (files.isEmpty) {
    test('no .gp fixtures found (copy your sample files to test/fixtures)', () {}, skip: 'no fixtures');
    return;
  }

  for (final name in files) {
    group(name, () {
      final score = GpxParserService.parseBytes(File('test/fixtures/$name').readAsBytesSync(), fileName: name);

      test('one measure end per master bar, in every track', () {
        for (final t in score.tracks) {
          expect(t.measureEndIndices.length, score.masterBars.length, reason: t.name);
        }
      });

      test('every bar covers its length (no early drift)', () {
        for (final t in score.tracks) {
          for (int b = 0; b < score.masterBars.length; b++) {
            double sum = 0;
            for (int i = t.barStartIndex(b); i <= t.measureEndIndices[b]; i++) {
              sum += t.beats[i].unswungDuration ?? t.beats[i].duration;
            }
            expect(sum, greaterThanOrEqualTo(score.masterBars[b].quarters - 0.01), reason: '${t.name} bar $b');
          }
        }
      });

      test('pitches are plausible for the instrument', () {
        for (final t in score.tracks) {
          for (final n in t.allNotes.where((n) => !n.isRest)) {
            expect(n.pitch, inInclusiveRange(0, 127));
            if (t.tuning.length == 4 && !t.isPercussion) {
              expect(n.pitch, lessThan(76), reason: '${t.name} looks an octave high');
            }
          }
        }
      });

      test('timeline is sorted and balanced', () {
        final grid = BarGrid(score.masterBars, score.playOrder);
        final channels = GpPlaybackPlanner.assignChannels(score.tracks);
        for (int i = 0; i < score.tracks.length; i++) {
          final e = GpTimelineBuilder.buildTrack(track: score.tracks[i], grid: grid, trackIndex: i, channel: channels[i], isMainTrack: i == 0);
          for (int k = 1; k < e.length; k++) {
            expect(e[k].timeMs, greaterThanOrEqualTo(e[k - 1].timeMs));
          }
          expect(e.where((x) => x.type == MidiEventType.noteOn).length, e.where((x) => x.type == MidiEventType.noteOff).length);
        }
      });

      test('matches golden summary', () {
        final golden = File('test/fixtures/$name.golden.json');
        final actual = const JsonEncoder.withIndent('  ').convert(summarize(name));
        if (Platform.environment['UPDATE_GOLDEN'] == '1') {
          golden.writeAsStringSync(actual);
          return;
        }
        if (!golden.existsSync()) {
          markTestSkipped('no golden yet; run with UPDATE_GOLDEN=1 after reviewing');
          return;
        }
        expect(actual, golden.readAsStringSync());
      });
    });
  }
}
