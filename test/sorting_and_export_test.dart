import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tab_generator/models/lick_preset.dart';
import 'package:tab_generator/screens/saved_presets_screen.dart';
import 'package:tab_generator/services/preset_storage_service.dart';

LickPreset createPreset({
  required String id,
  required String name,
  required DateTime createdAt,
  int tempo = 120,
}) {
  return LickPreset.fromJson({
    'id': id,
    'name': name,
    'tempo': tempo,
    'createdAt': createdAt.toIso8601String(),
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PresetStorageService Sorting & Encoding', () {
    final p1 = createPreset(id: '1', name: 'Zebra Lick', createdAt: DateTime(2026, 1, 10));
    final p2 = createPreset(id: '2', name: 'Apple Lick', createdAt: DateTime(2026, 1, 20));
    final p3 = createPreset(id: '3', name: 'Mango Lick', createdAt: DateTime(2026, 1, 15));

    test('sortPresets by Name alphabetical', () {
      final sortedAsc = PresetStorageService.sortPresets([p1, p2, p3], sortBy: 'Name', ascending: true);
      expect(sortedAsc.map((p) => p.name).toList(), ['Apple Lick', 'Mango Lick', 'Zebra Lick']);

      final sortedDesc = PresetStorageService.sortPresets([p1, p2, p3], sortBy: 'Name', ascending: false);
      expect(sortedDesc.map((p) => p.name).toList(), ['Zebra Lick', 'Mango Lick', 'Apple Lick']);
    });

    test('sortPresets by Creation Date', () {
      final sortedAsc = PresetStorageService.sortPresets([p1, p2, p3], sortBy: 'Creation Date', ascending: true);
      expect(sortedAsc.map((p) => p.id).toList(), ['1', '3', '2']); // Jan 10, Jan 15, Jan 20

      final sortedDesc = PresetStorageService.sortPresets([p1, p2, p3], sortBy: 'Creation Date', ascending: false);
      expect(sortedDesc.map((p) => p.id).toList(), ['2', '3', '1']); // Jan 20, Jan 15, Jan 10
    });

    test('encodePresets and decodePresets preserves active sorted order', () {
      final sortedByName = PresetStorageService.sortPresets([p1, p2, p3], sortBy: 'Name');
      final jsonStr = PresetStorageService.encodePresets(sortedByName);

      final imported = PresetStorageService.decodePresets(jsonStr);
      expect(imported.map((p) => p.name).toList(), ['Apple Lick', 'Mango Lick', 'Zebra Lick']);
    });
  });

  group('SavedPresetsScreen Sorting & Exporting', () {
    late LickPreset pZebra;
    late LickPreset pApple;
    late LickPreset pMango;
    late List<LickPreset> presets;

    setUp(() {
      pZebra = createPreset(id: '1', name: 'Zebra Lick', createdAt: DateTime(2026, 1, 10));
      pApple = createPreset(id: '2', name: 'Apple Lick', createdAt: DateTime(2026, 1, 20));
      pMango = createPreset(id: '3', name: 'Mango Lick', createdAt: DateTime(2026, 1, 15));
      presets = [pZebra, pApple, pMango];
    });

    testWidgets('renders sort dropdown with Creation Date and Name options', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedPresetsScreen(
              savedPresets: presets,
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
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('sort_presets_dropdown')), findsOneWidget);
      expect(find.text('Sort by:'), findsOneWidget);
      expect(find.text('Creation Date'), findsOneWidget);

      // Open dropdown
      await tester.tap(find.byKey(const Key('sort_presets_dropdown')));
      await tester.pumpAndSettle();

      expect(find.text('Name').hitTestable(), findsOneWidget);
      expect(find.text('Creation Date').hitTestable(), findsWidgets);
    });

    testWidgets('dynamically updates UI order when sort order changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedPresetsScreen(
              savedPresets: presets,
              initialSortBy: 'Creation Date',
              initialSortAscending: true,
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
            ),
          ),
        ),
      );

      // In Creation Date ascending order: Zebra (Jan 10), Mango (Jan 15), Apple (Jan 20)
      Finder listTiles = find.byType(ListTile);
      expect(tester.widget<Text>(find.descendant(of: listTiles.at(0), matching: find.byType(Text)).first).data, 'Zebra Lick');
      expect(tester.widget<Text>(find.descendant(of: listTiles.at(1), matching: find.byType(Text)).first).data, 'Mango Lick');
      expect(tester.widget<Text>(find.descendant(of: listTiles.at(2), matching: find.byType(Text)).first).data, 'Apple Lick');

      // Change to sort by Name
      await tester.tap(find.byKey(const Key('sort_presets_dropdown')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();

      // In Name alphabetical order: Apple, Mango, Zebra
      listTiles = find.byType(ListTile);
      expect(tester.widget<Text>(find.descendant(of: listTiles.at(0), matching: find.byType(Text)).first).data, 'Apple Lick');
      expect(tester.widget<Text>(find.descendant(of: listTiles.at(1), matching: find.byType(Text)).first).data, 'Mango Lick');
      expect(tester.widget<Text>(find.descendant(of: listTiles.at(2), matching: find.byType(Text)).first).data, 'Zebra Lick');
    });

    testWidgets('Export All exports presets in the active sorted order', (tester) async {
      List<LickPreset>? exportedList;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedPresetsScreen(
              savedPresets: presets,
              initialSortBy: 'Creation Date',
              initialSortAscending: true,
              isPreviewPlaying: false,
              isPreviewLooping: false,
              onPlayPreview: (_) {},
              onStopPreview: () {},
              onTogglePreviewLoop: () {},
              onLoadPreset: (_) {},
              onDeletePresets: (_) {},
              onRenamePreset: (_, __) {},
              onExportPresets: (exported) {
                exportedList = exported;
              },
              onReorderPresets: (_, __) {},
              onImport: () {},
            ),
          ),
        ),
      );

      // Select Name sort
      await tester.tap(find.byKey(const Key('sort_presets_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();

      // Tap Export All
      await tester.tap(find.text('Export All'));
      await tester.pumpAndSettle();

      expect(exportedList, isNotNull);
      expect(exportedList!.map((p) => p.name).toList(), ['Apple Lick', 'Mango Lick', 'Zebra Lick']);

      // Verify that encoding and decoding preserves this order
      final jsonStr = PresetStorageService.encodePresets(exportedList!);
      final reimported = PresetStorageService.decodePresets(jsonStr);
      expect(reimported.map((p) => p.name).toList(), ['Apple Lick', 'Mango Lick', 'Zebra Lick']);
    });

    testWidgets('Export Selected exports selected presets in the active sorted order', (tester) async {
      List<LickPreset>? exportedList;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedPresetsScreen(
              savedPresets: presets,
              initialSortBy: 'Name',
              initialSortAscending: true,
              isPreviewPlaying: false,
              isPreviewLooping: false,
              onPlayPreview: (_) {},
              onStopPreview: () {},
              onTogglePreviewLoop: () {},
              onLoadPreset: (_) {},
              onDeletePresets: (_) {},
              onRenamePreset: (_, __) {},
              onExportPresets: (exported) {
                exportedList = exported;
              },
              onReorderPresets: (_, __) {},
              onImport: () {},
            ),
          ),
        ),
      );

      // In alphabetical order: Apple (index 0), Mango (index 1), Zebra (index 2)
      // Long press Zebra and Apple to select them
      await tester.longPress(find.text('Zebra Lick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apple Lick'));
      await tester.pumpAndSettle();

      // Tap Export Selected
      await tester.tap(find.byTooltip('Export Selected'));
      await tester.pumpAndSettle();

      expect(exportedList, isNotNull);
      expect(exportedList!.length, 2);
      // Even though Zebra was selected first, exported order follows active UI sort order (Apple then Zebra)
      expect(exportedList!.map((p) => p.name).toList(), ['Apple Lick', 'Zebra Lick']);
    });
  });
}
