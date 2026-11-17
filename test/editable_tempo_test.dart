import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tab_generator/models/lick_preset.dart';
import 'package:tab_generator/screens/saved_presets_screen.dart';
import 'package:tab_generator/services/preset_storage_service.dart';

LickPreset createPreset({
  String id = 'p1',
  String name = 'Test Lick',
  int tempo = 120,
}) {
  return LickPreset.fromJson({
    'id': id,
    'name': name,
    'tempo': tempo,
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LickPreset tempo updates', () {
    test('updateTempo and copyWithTempo update tempo correctly', () {
      final p = createPreset(tempo: 120);
      final p1 = p.updateTempo(130);
      expect(p1.tempo, 130);
      expect(p1.id, p.id);

      final p2 = p.copyWithTempo(140);
      expect(p2.tempo, 140);
      expect(p2.id, p.id);
    });
  });

  group('PresetStorageService tempo updates', () {
    test('updatePresetTempo persists the new tempo', () async {
      final storage = PresetStorageService();
      final p1 = createPreset(id: 'p1', tempo: 100);
      final p2 = createPreset(id: 'p2', tempo: 150);

      await storage.savePresets([p1, p2]);

      await storage.updatePresetTempo('p1', 115);

      final loaded = await storage.loadPresets();
      expect(loaded.length, 2);
      expect(loaded.firstWhere((p) => p.id == 'p1').tempo, 115);
      expect(loaded.firstWhere((p) => p.id == 'p2').tempo, 150);
    });

    test('updatePreset persists the updated preset', () async {
      final storage = PresetStorageService();
      final p1 = createPreset(id: 'p1', tempo: 100);
      await storage.savePresets([p1]);

      final updated = p1.copyWith(tempo: 125, name: 'Renamed Lick');
      await storage.updatePreset(updated);

      final loaded = await storage.loadPresets();
      expect(loaded.length, 1);
      expect(loaded.first.tempo, 125);
      expect(loaded.first.name, 'Renamed Lick');
    });
  });

  group('InlineTempoEditor Widget', () {
    testWidgets('renders initial tempo and allows digital keyboard editing', (tester) async {
      int? changedTempo;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: InlineTempoEditor(
                tempo: 120,
                onChanged: (val) => changedTempo = val,
              ),
            ),
          ),
        ),
      );

      // Verify initial tempo
      expect(find.text('120'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);

      // Verify digital keyboard input
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.keyboardType, TextInputType.number);

      // Tap and enter a number
      await tester.tap(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), '135');
      await tester.pump();

      // Tap outside to unfocus
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(changedTempo, 135);
    });

    testWidgets('increment and decrement buttons adjust tempo by 1', (tester) async {
      int currentTempo = 120;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: InlineTempoEditor(
                    tempo: currentTempo,
                    onChanged: (val) {
                      setState(() {
                        currentTempo = val;
                      });
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );

      // Tap increment button (up arrow)
      final incFinder = find.byIcon(Icons.arrow_drop_up);
      expect(incFinder, findsOneWidget);
      await tester.tap(incFinder);
      await tester.pumpAndSettle();

      expect(currentTempo, 121);
      expect(find.text('121'), findsOneWidget);

      // Tap decrement button (down arrow)
      final decFinder = find.byIcon(Icons.arrow_drop_down);
      expect(decFinder, findsOneWidget);
      await tester.tap(decFinder);
      await tester.pumpAndSettle();

      expect(currentTempo, 120);
      expect(find.text('120'), findsOneWidget);
    });
  });

  group('SavedPresetsScreen Inline Tempo Integration', () {
    testWidgets('replaces static tempo text with editable widget and auto-saves', (tester) async {
      final storage = PresetStorageService();
      final preset = createPreset(id: 'p1', name: 'My Blues Lick', tempo: 90);
      await storage.savePresets([preset]);

      List<LickPreset> savedPresets = [preset];
      int? updatedTempoCallback;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedPresetsScreen(
              savedPresets: savedPresets,
              isPreviewPlaying: false,
              isPreviewLooping: false,
              onPlayPreview: (_) {},
              onStopPreview: () {},
              onTogglePreviewLoop: () {},
              onLoadPreset: (_) {},
              onDeletePresets: (_) {},
              onRenamePreset: (_, __) {},
              onExportPresets: (_) {},
              onReorderPresets: (_, __) {},
              onImport: () {},
              onUpdateTempo: (id, tempo) {
                updatedTempoCallback = tempo;
              },
              storageService: storage,
            ),
          ),
        ),
      );

      // Verify that the editable widget is present
      expect(find.byType(InlineTempoEditor), findsOneWidget);
      expect(find.text('90'), findsOneWidget);

      // 1. Test Increment Button in Preset item
      await tester.tap(find.byIcon(Icons.arrow_drop_up));
      await tester.pumpAndSettle();

      expect(find.text('91'), findsOneWidget);
      expect(updatedTempoCallback, 91);

      // Verify persisted to storage
      var stored = await storage.loadPresets();
      expect(stored.first.tempo, 91);

      // 2. Test Decrement Button in Preset item
      final decFinder = find.descendant(
        of: find.byType(InlineTempoEditor),
        matching: find.byIcon(Icons.arrow_drop_down),
      );
      await tester.tap(decFinder);
      await tester.pumpAndSettle();

      expect(find.text('90'), findsOneWidget);
      expect(updatedTempoCallback, 90);

      stored = await storage.loadPresets();
      expect(stored.first.tempo, 90);

      // 3. Test tapping to input number and tap outside to unfocus/save
      await tester.tap(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), '140');
      await tester.pump();

      // Tap outside (e.g. top of screen)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('140'), findsOneWidget);
      expect(updatedTempoCallback, 140);

      stored = await storage.loadPresets();
      expect(stored.first.tempo, 140);
    });
  });
}
