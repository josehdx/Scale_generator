import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/models/lick_preset.dart';
import 'package:tab_generator/models/preset_sanitizer.dart';
import 'package:tab_generator/scale_engine.dart';
import 'package:tab_generator/services/preset_storage_service.dart';
import 'package:tab_generator/utils/tab_sequence_builder.dart';

// NOTE: replace `tab_generator` with the `name:` from your pubspec.yaml.

LickPreset preset([Map<String, dynamic> json = const {}]) => LickPreset.fromJson(Map<String, dynamic>.from(json));

void main() {
  late ScaleEngine engine;
  late TabSequenceBuilder builder;
  setUp(() {
    engine = ScaleEngine();
    builder = TabSequenceBuilder(engine: engine);
  });

  group('2.1 tuning follows the preset', () {
    test('generating in Drop D switches the engine before generating', () {
      engine.setTuning('Standard E');
      builder.buildSequenceForPreset(preset({'tuning': 'Drop D', 'key': 'D', 'startFret': 0}));
      expect(engine.openStrings[6], 38);
    });

    test('an unknown tuning name does not pollute the tuning list', () {
      final before = engine.tunings.keys.toList();
      builder.buildSequenceForPreset(preset({'tuning': 'Imaginary'}));
      expect(engine.tunings.keys.toList(), before);
    });
  });

  group('2.4 manual mode', () {
    test('duration markers are understood, not dropped', () {
      final seq = builder.parseManualTab('6:5(8), r, 5:7+4:7, 6:9(Q)');
      expect(seq.map((n) => n.sublist(0, 3)).toList(), [
        [6, 5, 1],
        [-1, -1, 0],
        [5, 7, 0],
        [4, 7, 0],
        [6, 9, 2],
      ]);
      // token index, used to map a selection back to the text
      expect(seq.map((n) => n[3]).toList(), [0, 1, 2, 2, 3]);
    });

    test('strings above 6 are rejected (the tunings only have 6)', () {
      expect(builder.parseManualTab('7:5, 6:5'), [
        [6, 5, 0, 1]
      ]);
    });

    test('token list matches the token indexes', () {
      expect(TabSequenceBuilder.manualTokens(' 6:5 , , r ,5:7'), ['6:5', 'r', '5:7']);
    });

    test('durations reach the beats', () {
      final beats = builder.sequenceToBeats(builder.parseManualTab('6:5(8), 6:7(Q), 6:9'));
      expect(beats.map((b) => b.duration).toList(), [0.5, 1.0, 0.25]);
    });
  });

  group('2.6 notes per measure / rate', () {
    test('any rhythm pattern', () {
      expect(builder.calculateNotesPerMeasure('Auto', 'Straight 16ths'), 16);
      expect(builder.calculateNotesPerMeasure('Auto', 'Straight 8ths'), 8);
      expect(builder.calculateNotesPerMeasure('3/4', 'Straight 8ths'), 6);
      expect(builder.calculateNotesPerMeasure('Auto', 'Gallop (8-16-16)'), 12);
      expect(builder.calculateNotesPerMeasure('5/4', 'Straight 16ths'), 20);
    });

    test('Auto with a 10-note motif is one bar of 10 notes', () {
      expect(builder.calculateNotesPerMeasure('Auto', 'Straight 16ths', autoNotes: 10), 10);
    });

    test('notes per second is real', () {
      expect(builder.notesPerSecond(120, ['8th']), closeTo(4, 1e-9));
      expect(builder.notesPerSecond(120, ['16th']), closeTo(8, 1e-9));
      expect(builder.notesPerSecond(120, ['Quarter']), closeTo(2, 1e-9));
      expect(builder.notesPerSecond(120, ['8th', '16th', '16th']), closeTo(6, 1e-9));
      expect(builder.notesPerSecond(0, ['16th']), 0);
    });

    test('Single String Horizontal honours the pathway', () {
      final base = {'system': 'Single String Horizontal', 'fragment': '1', 'startFret': 5};
      final linear = builder.buildSequenceForPreset(preset({...base, 'pathway': 'Straight Linear', 'direction': 'One-Way (Ascend)'}));
      final triplet = builder.buildSequenceForPreset(preset({...base, 'pathway': '3-Step Triplet', 'direction': 'One-Way (Ascend)'}));
      expect(linear, isNotEmpty);
      expect(triplet.toString(), isNot(linear.toString()));
    });
  });

  group('2.2 preset crash paths', () {
    test('fromJson survives values of the wrong type', () {
      final p = preset({'tempo': 'fast', 'startFret': null, 'key': 5, 'createdAt': 'not a date', 'endRests': 3.0});
      expect(p.tempo, 120);
      expect(p.key, 'C');
      expect(p.endRests, 3);
    });

    test('sanitizeFields heals unknown dropdown values and ranges', () {
      final healed = PresetSanitizer.sanitizeFields(
        preset({'key': 'H', 'scale': 'Nope', 'tuning': 'Nope', 'system': 'Nope', 'pathway': 'Nope', 'direction': 'Nope', 'timeSignature': '13/4', 'rhythm': 'Nope', 'tempo': 0, 'endRests': 9999, 'patternMultiplier': 0, 'instrumentIndex': 99, 'fragment': '9-0'}),
        keys: engine.noteMap.keys.toSet(),
        scales: engine.scaleFormulas.keys.toSet(),
        tunings: engine.tunings.keys.toSet(),
        systems: {'Box Position / CAGED', 'Manual Entry'},
        pathways: {'Straight Linear', 'Custom Motif Builder'},
        directions: {'Ascend -> Descend'},
        timeSignatures: {'Auto', '4/4'},
        rhythms: {'Straight 16ths'},
        instrumentIndexes: {27, 25},
      );
      expect(healed.key, 'C');
      expect(engine.scaleFormulas.keys, contains(healed.scale));
      expect(engine.tunings.keys, contains(healed.tuning));
      expect(healed.system, 'Box Position / CAGED');
      expect(healed.pathway, 'Straight Linear');
      expect(healed.timeSignature, 'Auto');
      expect(healed.tempo, 40);
      expect(healed.endRests, 64);
      expect(healed.patternMultiplier, 1);
      expect(healed.instrumentIndex, 27);
      expect(healed.fragment, '6-1');
    });

    test('one corrupt preset costs only itself', () {
      int skipped = -1;
      final list = PresetStorageService.decodePresets(
        '[{"name":"ok"}, 5, "x", {"name":"ok2","tempo":"fast"}]',
        onSkipped: (n) => skipped = n,
      );
      expect(list.map((p) => p.name).toList(), ['ok', 'ok2']);
      expect(skipped, 2);
    });

    test('a non-list file is rejected as a whole', () {
      expect(() => PresetStorageService.decodePresets('{"a":1}'), throwsFormatException);
    });
  });
}
