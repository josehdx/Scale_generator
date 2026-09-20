import 'package:flutter/material.dart';
import '../models/lick_preset.dart';

class SavedPresetsScreen extends StatefulWidget {
  final List<LickPreset> savedPresets;
  final Function(LickPreset) onLoadPreset;
  final Function(int) onDeletePreset;
  final Function(List<LickPreset>) onExportPresets;
  final VoidCallback onImport;

  const SavedPresetsScreen({
    super.key,
    required this.savedPresets,
    required this.onLoadPreset,
    required this.onDeletePreset,
    required this.onExportPresets,
    required this.onImport,
  });

  @override
  State<SavedPresetsScreen> createState() => _SavedPresetsScreenState();
}

class _SavedPresetsScreenState extends State<SavedPresetsScreen> {
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    // Select all presets by default on load
    _selectedIds.addAll(widget.savedPresets.map((e) => e.id));
  }

  @override
  void didUpdateWidget(covariant SavedPresetsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Remove IDs that were deleted
    _selectedIds.removeWhere((id) => !widget.savedPresets.any((p) => p.id == id));
    // Auto-select newly created presets
    for (var preset in widget.savedPresets) {
      if (!oldWidget.savedPresets.any((p) => p.id == preset.id)) {
        _selectedIds.add(preset.id);
      }
    }
  }

  void _toggleSelectAll(bool? selectAll) {
    setState(() {
      if (selectAll == true) {
        _selectedIds.addAll(widget.savedPresets.map((e) => e.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isAllSelected = widget.savedPresets.isNotEmpty &&
        _selectedIds.length == widget.savedPresets.length;

    List<LickPreset> selectedList = widget.savedPresets
        .where((p) => _selectedIds.contains(p.id))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: isAllSelected,
                        onChanged: widget.savedPresets.isEmpty ? null : _toggleSelectAll,
                      ),
                      const Text("Select All", style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(
                    "${_selectedIds.length} / ${widget.savedPresets.length} Selected",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () => widget.onExportPresets(selectedList),
                      icon: const Icon(Icons.download_for_offline, size: 18),
                      label: Text("Export (${_selectedIds.length})"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.onImport,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text("Import File"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: widget.savedPresets.isEmpty
              ? const Center(
                  child: Text(
                    "No saved presets yet.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.savedPresets.length,
                  itemBuilder: (context, index) {
                    final preset = widget.savedPresets[index];
                    final isSelected = _selectedIds.contains(preset.id);

                    return ListTile(
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(preset.id);
                            } else {
                              _selectedIds.remove(preset.id);
                            }
                          });
                        },
                      ),
                      title: Text(preset.name),
                      subtitle: Text(
                          "${preset.tempo} BPM | ${preset.rhythm} | Fret ${preset.startFret}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => widget.onDeletePreset(index),
                      ),
                      onTap: () => widget.onLoadPreset(preset),
                    );
                  },
                ),
        ),
      ],
    );
  }
}