import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lick_preset.dart';

class SavedPresetsScreen extends StatelessWidget {
  final List<LickPreset> savedPresets;
  final Function(LickPreset preset) onLoadPreset;
  final Function(int index) onDeletePreset;
  final VoidCallback onExportAll;

  const SavedPresetsScreen({
    super.key,
    required this.savedPresets,
    required this.onLoadPreset,
    required this.onDeletePreset,
    required this.onExportAll,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Stored Presets (${savedPresets.length})",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: onExportAll,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text("Export All"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: savedPresets.isEmpty
                ? const Center(
                    child: Text(
                      "No saved presets yet.\nUse the bookmark icon on any screen to store licks!",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: savedPresets.length,
                    itemBuilder: (context, index) {
                      final item = savedPresets[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "Tuning: ${item.tuning} | Tempo: ${item.tempo} BPM\nSaved: ${item.createdAt.toString().substring(0, 16)}",
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_circle_fill,
                                    color: Colors.green),
                                tooltip: 'Load Preset',
                                onPressed: () => onLoadPreset(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                tooltip: 'Copy Tab',
                                onPressed: () {
                                  Clipboard.setData(
                                          ClipboardData(text: item.tabOutput))
                                      .then((_) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              "Tab copied to clipboard!")),
                                    );
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.redAccent, size: 20),
                                tooltip: 'Delete Preset',
                                onPressed: () => onDeletePreset(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}