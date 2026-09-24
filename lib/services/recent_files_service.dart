import 'dart:convert';
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
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (e) {
      // Swallow silently
    }
    return [];
  }

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