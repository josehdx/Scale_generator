import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lick_preset.dart';

/// Handles all preset and session persistence: SharedPreferences read/write,
/// JSON file export (via Share), and JSON file import (via FilePicker).
///
/// Every method is side-effect free with respect to Flutter widget state —
/// callers are responsible for calling `setState` with returned values.
class PresetStorageService {
  static const String _storageKey = 'auto_saved_lick_presets';
  static const String _backupKey = 'auto_saved_lick_presets_corrupt_backup';
  static const String _sessionKey = 'last_session_state';

  /// Number of stored presets that could not be read in the last [loadPresets].
  int lastSkippedCount = 0;

  /// Decodes a JSON list one element at a time, so a single corrupt preset
  /// costs only itself and never the whole library.
  static List<LickPreset> decodePresets(String jsonString, {void Function(int skipped)? onSkipped}) {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! List) throw const FormatException('Preset file is not a list');
    final List<LickPreset> out = [];
    int skipped = 0;
    for (final dynamic e in decoded) {
      try {
        if (e is! Map) throw const FormatException('not an object');
        out.add(LickPreset.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        skipped++;
      }
    }
    onSkipped?.call(skipped);
    return out;
  }

  // ── Preset CRUD ────────────────────────────────────────────────────────────

  /// Loads the saved preset list from SharedPreferences.
  ///
  /// If the stored text cannot be parsed at all, it is copied to a backup key
  /// BEFORE an empty list is returned, so the next save cannot destroy it.
  Future<List<LickPreset>> loadPresets() async {
    lastSkippedCount = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) return [];
      try {
        return decodePresets(jsonString, onSkipped: (n) => lastSkippedCount = n);
      } catch (e) {
        debugPrint('PresetStorageService.loadPresets: corrupt data, backing up ($e)');
        await prefs.setString(_backupKey, jsonString);
        return [];
      }
    } catch (e) {
      debugPrint('PresetStorageService.loadPresets: $e');
    }
    return [];
  }

  /// Persists [presets] to SharedPreferences.
  Future<void> savePresets(List<LickPreset> presets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(presets.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('PresetStorageService.savePresets: $e');
    }
  }

  /// Updates the tempo for a preset by [id] and persists the updated presets list.
  Future<void> updatePresetTempo(String id, int newTempo) async {
    final presets = await loadPresets();
    final index = presets.indexWhere((p) => p.id == id);
    if (index != -1) {
      presets[index] = presets[index].copyWith(tempo: newTempo);
      await savePresets(presets);
    }
  }

  /// Updates an existing preset matching [preset.id] and persists the list.
  Future<void> updatePreset(LickPreset preset) async {
    final presets = await loadPresets();
    final index = presets.indexWhere((p) => p.id == preset.id);
    if (index != -1) {
      presets[index] = preset;
      await savePresets(presets);
    }
  }

  // ── Session ────────────────────────────────────────────────────────────────

  /// Loads the last auto-saved session preset, or `null` if none exists.
  Future<LickPreset?> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_sessionKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        return LickPreset.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('PresetStorageService.loadSession: $e');
    }
    return null;
  }

  Timer? _sessionDebounce;
  LickPreset? _pendingSession;

  /// Saves [preset] as the current session snapshot. Writes are debounced: the
  /// session used to be rewritten (with the full tab text) on every keystroke.
  Future<void> saveSession(LickPreset preset) async {
    _pendingSession = preset;
    _sessionDebounce?.cancel();
    _sessionDebounce = Timer(const Duration(milliseconds: 800), flushSession);
  }

  /// Writes a pending session immediately (call from dispose / app pause).
  Future<void> flushSession() async {
    _sessionDebounce?.cancel();
    final LickPreset? p = _pendingSession;
    if (p == null) return;
    _pendingSession = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(p.toJson()));
    } catch (e) {
      debugPrint('PresetStorageService.saveSession: $e');
    }
  }

  // ── Sorting ───────────────────────────────────────────────────────────────

  /// Sorts a list of [presets] by [sortBy] ('Creation Date' or 'Name').
  /// If [sortBy] is 'Creation Date', sorts by [LickPreset.createdAt] (fallback to list index/ID).
  /// If [sortBy] is 'Name', sorts alphabetically by [LickPreset.name].
  static List<LickPreset> sortPresets(
    List<LickPreset> presets, {
    String sortBy = 'Creation Date',
    bool ascending = true,
  }) {
    final list = List<LickPreset>.from(presets);
    if (sortBy == 'Name') {
      list.sort((a, b) {
        final comp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return ascending ? comp : -comp;
      });
    } else if (sortBy == 'Creation Date') {
      list.sort((a, b) {
        final comp = a.createdAt.compareTo(b.createdAt);
        if (comp != 0) return ascending ? comp : -comp;
        return ascending ? a.id.compareTo(b.id) : b.id.compareTo(a.id);
      });
    }
    return list;
  }

  /// Encodes [presets] to a formatted JSON string, preserving order.
  /// If [sortBy] is specified, sorts the presets before serialization.
  static String encodePresets(
    List<LickPreset> presets, {
    String? sortBy,
    bool ascending = true,
  }) {
    List<LickPreset> toEncode = List<LickPreset>.from(presets);
    if (sortBy != null) {
      toEncode = sortPresets(toEncode, sortBy: sortBy, ascending: ascending);
    }
    return const JsonEncoder.withIndent('  ').convert(toEncode.map((e) => e.toJson()).toList());
  }

  // ── Export / Import ────────────────────────────────────────────────────────

  /// Exports [presets] as a JSON file via the platform Share sheet.
  /// Throws on error — callers should display a SnackBar on catch.
  ///
  /// [sharePositionOrigin] is required on iPad (the share sheet is a popover).
  /// If [sortBy] is specified, sorts [presets] using [sortPresets] before writing.
  Future<void> exportPresets(
    List<LickPreset> presets, {
    Rect? sharePositionOrigin,
    String? sortBy,
    bool ascending = true,
  }) async {
    if (presets.isEmpty) return;
    List<LickPreset> toExport = List<LickPreset>.from(presets);
    if (sortBy != null) {
      toExport = sortPresets(toExport, sortBy: sortBy, ascending: ascending);
    }
    final jsonString = const JsonEncoder.withIndent('  ').convert(toExport.map((e) => e.toJson()).toList());
    final directory = await getTemporaryDirectory();
    final safeName = toExport.length == 1
        ? toExport.first.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        : 'TabStudio_Batch_${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${directory.path}/$safeName.json');
    await file.writeAsString(jsonString);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Tab Generator Studio Presets',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Imports presets from a user-selected JSON file.
  ///
  /// Returns the parsed list on success, `null` if the user cancelled. Corrupt
  /// entries are skipped (counted in [lastSkippedCount]).
  /// Throws on parse/read error — callers should display a SnackBar on catch.
  Future<List<LickPreset>?> importPresets() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return null; // user cancelled
    }
    final jsonString = await File(result.files.first.path!).readAsString();
    lastSkippedCount = 0;
    return decodePresets(jsonString, onSkipped: (n) => lastSkippedCount = n);
  }
}
