import 'package:flutter/material.dart';
import '../models/lick_preset.dart';

class SavedPresetsScreen extends StatelessWidget {
  final List<LickPreset> savedPresets;
  final Function(LickPreset) onLoadPreset;
  final Function(int) onDeletePreset;
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: onExportAll,
            icon: const Icon(Icons.copy),
            label: const Text("Export All to Clipboard"),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: savedPresets.length,
            itemBuilder: (context, index) {
              final preset = savedPresets[index];
              return ListTile(
                title: Text(preset.name),
                subtitle: Text("${preset.tempo} BPM | ${preset.rhythm} | Fret ${preset.startFret}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => onDeletePreset(index),
                ),
                onTap: () => onLoadPreset(preset),
              );
            },
          ),
        ),
      ],
    );
  }
}