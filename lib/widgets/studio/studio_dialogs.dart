import 'package:flutter/material.dart';
import 'dart:math';

/// Extracted dialogs and bottom sheets for the studio screen.
class StudioDialogs {
  
  /// Shows the "Save Preset" dialog and returns the user-entered name, or null.
  static Future<String?> showSavePresetDialog(BuildContext context, String initialName) async {
    TextEditingController nameController = TextEditingController(text: initialName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Save Lick Preset', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Preset Name',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            child: const Text('Save'),
            onPressed: () {
              String name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop(name);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Shows the manual delete menu bottom sheet. Returns [action, count] or null.
  /// 
  /// Action is 'backspace' or 'clear'.
  static Future<Map<String, dynamic>?> showManualDeleteMenu(BuildContext context, {required bool hasSelection}) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSelection)
                 ListTile(
                  leading: const Icon(Icons.highlight_remove, color: Colors.redAccent),
                  title: const Text('Delete Selected Notes', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(ctx, {'action': 'delete_selection'}),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.backspace, color: Colors.orange),
                  title: const Text('Backspace (Delete Last Note)', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(ctx, {'action': 'backspace', 'count': 1}),
                ),
                ListTile(
                  leading: const Icon(Icons.fast_rewind, color: Colors.orangeAccent),
                  title: const Text('Delete Last 4 Notes', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(ctx, {'action': 'backspace', 'count': 4}),
                ),
              ],
              const Divider(color: Colors.grey),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Clear Entire Tab', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () => Navigator.pop(ctx, {'action': 'clear'}),
              ),
            ],
          ),
        );
      },
    );
  }
}

