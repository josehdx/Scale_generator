import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentFilesService {
  RecentFilesService._();

  static const String _key = 'recent_gp_files';
  static const int _maxEntries = 10;

  static Future<List<Map<String, String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_key);
      if (jsonStr != null) {
        final dynamic decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          final List<Map<String, String>> out = [];
          for (final dynamic e in decoded) {
            // one malformed entry must not hide the others
            if (e is Map && e['name'] is String) {
              out.add({'name': e['name'] as String, 'path': (e['path'] as String?) ?? ''});
            }
          }
          return out;
        }
      }
    } catch (_) {
      // unreadable list = empty list
    }
    return [];
  }

  /// The stored absolute path goes stale when iOS changes the app container
  /// (after an update / restore). Files are copied into the documents folder
  /// under their own name, so the name is resolved against the CURRENT
  /// documents directory first and the stored path is only a fallback.
  /// Returns null when the file is gone.
  static Future<String?> resolve(String name, String storedPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final String current = '${docs.path}/$name';
      if (await File(current).exists()) return current;
    } catch (_) {}
    if (storedPath.isNotEmpty && await File(storedPath).exists()) return storedPath;
    return null;
  }

  static Future<List<Map<String, String>>> add(
    List<Map<String, String>> current,
    String name,
    String path,
  ) async {
    final updated = List<Map<String, String>>.from(current);
    // identify entries by name: the path part may differ between app containers
    updated.removeWhere((e) => e['name'] == name);
    updated.insert(0, {'name': name, 'path': path});
    if (updated.length > _maxEntries) {
      updated.removeRange(_maxEntries, updated.length);
    }
    await _persist(updated);
    return updated;
  }

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
