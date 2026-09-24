import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lick_preset.dart';

class PresetStorageService {
  static const String _storageKey = 'auto_saved_lick_presets';
  static const String _sessionKey = 'last_session_state';

  Future<List<LickPreset>> loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        return decoded.map((e) => LickPreset.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('PresetStorageService.loadPresets: $e');
    }
    return [];
  }

  Future<void> savePresets(List<LickPreset> presets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode(presets.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('PresetStorageService.savePresets: $e');
    }
  }

  Future<LickPreset?> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_sessionKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        return LickPreset.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('PresetStorageService.loadSession: $e');
    }
    return null;
  }

  Future<void> saveSession(LickPreset preset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(preset.toJson()));
    } catch (e) {
      debugPrint('PresetStorageService.saveSession: $e');
    }
  }

  Future<void> exportPresets(List<LickPreset> presets) async {
    if (presets.isEmpty) return;
    final jsonString =
        const JsonEncoder.withIndent('  ').convert(presets.map((e) => e.toJson()).toList());
    final directory = await getTemporaryDirectory();
    final safeName = presets.length == 1
        ? presets.first.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        : 'TabStudio_Batch_${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${directory.path}/$safeName.json');
    await file.writeAsString(jsonString);
    await Share.shareXFiles(
        [XFile(file.path)], text: 'Tab Generator Studio Presets');
  }

  Future<List<LickPreset>?> importPresets() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return null;
    }
    final jsonString = await File(result.files.first.path!).readAsString();
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded
        .map((e) => LickPreset.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}