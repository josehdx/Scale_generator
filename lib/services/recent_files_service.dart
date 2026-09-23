import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and retrieves the list of recently opened GP files.
///
/// Each entry is a `Map<String, String>` with keys `'name'` and `'path'`.
/// Methods return the updated list so callers can apply it directly via
/// `setState`.
class RecentFilesService {
  RecentFilesService._();

  static const String _key = 'recent_gp_files';
  static const int _maxEntries = 10;

  /// Loads and returns the persisted recent-files list.
  ///
  /// Returns an empty list if nothing has been saved yet or on any error.
  static Future<List<Map<String, String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_key);
      if (jsonStr != null) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (e) {
      // Swallow silently; return empty list below.
    }
    return [];
  }

  /// Adds or promotes [name]/[path] to the top of [current], persists the
  /// result (capped at [_maxEntries]), and returns the updated list.
  static Future<List<Map<String, String>>> add(
    List<Map<String, String>> current,
    String name,
    String path,
  ) async {
    final updated = List<Map<String, String>>.from(current);
    updated.removeWhere((e) => e['path'] == path);
    updated.insert(0, {'name': name, 'path': path});
    if (updated.length > _maxEntries) {
      updated.removeRange(_maxEntries, updated.length);
    }
    await _persist(updated);
    return updated;
  }

  /// Removes the entry with the given [path] from [current], persists, and
  /// returns the updated list.
  static Future<List<Map<String, String>>> remove(
    List<Map<String, String>> current,
    String path,
  ) async {
    final updated = List<Map<String, String>>.from(current)
      ..removeWhere((e) => e['path'] == path);
    await _persist(updated);
    return updated;
  }

  static Future<void> _persist(List<Map<String, String>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }
}

