import 'package:flutter/material.dart';
import '../models/lick_preset.dart';

class SavedPresetsScreen extends StatefulWidget {
  final List<LickPreset> savedPresets;
  final Function(LickPreset) onLoadPreset;
  final Function(List<String>) onDeletePresets;
  final Function(String, String) onRenamePreset;
  final Function(List<LickPreset>) onExportPresets;
  final VoidCallback onImport;

  const SavedPresetsScreen({
    super.key,
    required this.savedPresets,
    required this.onLoadPreset,
    required this.onDeletePresets,
    required this.onRenamePreset,
    required this.onExportPresets,
    required this.onImport,
  });

  @override
  State<SavedPresetsScreen> createState() => _SavedPresetsScreenState();
}

class _SavedPresetsScreenState extends State<SavedPresetsScreen> {
  final Set<String> _selectedIds = {};

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _showRenameDialog(BuildContext context, LickPreset preset) {
    TextEditingController controller = TextEditingController(text: preset.name);
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Rename Preset"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Preset Name",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  widget.onRenamePreset(preset.id, controller.text.trim());
                }
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasSelection = _selectedIds.isNotEmpty;

    return Column(
      children: [
        // DYNAMIC TOP BAR (Switches context if items are selected)
        Container(
          padding: const EdgeInsets.all(8.0),
          color: hasSelection ? Colors.blue.withOpacity(0.15) : Colors.transparent,
          child: hasSelection
              ? Row(
                  children: [
                    Checkbox(
                      value: _selectedIds.length == widget.savedPresets.length,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedIds.addAll(widget.savedPresets.map((e) => e.id));
                          } else {
                            _selectedIds.clear();
                          }
                        });
                      },
                    ),
                    Text("${_selectedIds.length} Selected", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.file_upload, color: Colors.blueAccent),
                      tooltip: "Export Selected",
                      onPressed: () {
                        final toExport = widget.savedPresets
                            .where((p) => _selectedIds.contains(p.id))
                            .toList();
                        widget.onExportPresets(toExport);
                        _clearSelection();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      tooltip: "Delete Selected",
                      onPressed: () {
                        widget.onDeletePresets(_selectedIds.toList());
                        _clearSelection();
                      },
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Saved Licks (${widget.savedPresets.length})", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.file_upload, size: 16),
                          label: const Text("Export All"),
                          onPressed: () => widget.onExportPresets(widget.savedPresets),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.file_download, size: 16),
                          label: const Text("Import"),
                          onPressed: widget.onImport,
                        ),
                      ],
                    )
                  ],
                ),
        ),
        
        // LIST OF PRESETS
        Expanded(
          child: widget.savedPresets.isEmpty
              ? const Center(
                  child: Text(
                    "No presets saved yet.\nGenerate a lick and press the Bookmark icon!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.savedPresets.length,
                  itemBuilder: (context, index) {
                    final preset = widget.savedPresets[index];
                    bool isSelected = _selectedIds.contains(preset.id);
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.grey.shade900,
                      child: ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(preset.id),
                            ),
                            const CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              child: Icon(Icons.music_note, color: Colors.white),
                            ),
                          ],
                        ),
                        title: Text(preset.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Tempo: ${preset.tempo} BPM | System: ${preset.system}\nGenerated: ${preset.createdAt.toString().split('.')[0]}"),
                        isThreeLine: true,
                        
                        // If selecting mode is active, disable standard popup actions to avoid confusion
                        trailing: hasSelection 
                          ? null 
                          : PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'load') widget.onLoadPreset(preset);
                                if (value == 'rename') _showRenameDialog(context, preset);
                                if (value == 'delete') widget.onDeletePresets([preset.id]);
                              },
                              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                const PopupMenuItem<String>(
                                  value: 'load',
                                  child: ListTile(
                                    leading: Icon(Icons.open_in_new, color: Colors.greenAccent),
                                    title: Text('Load Preset'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'rename',
                                  child: ListTile(
                                    leading: Icon(Icons.edit, color: Colors.amberAccent),
                                    title: Text('Rename'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete, color: Colors.redAccent),
                                    title: Text('Delete'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                            
                        // Tapping tile selects it if selection mode is active, otherwise loads it
                        onTap: () {
                          if (hasSelection) {
                            _toggleSelection(preset.id);
                          } else {
                            widget.onLoadPreset(preset);
                          }
                        },
                        
                        // Long press to quickly start a selection
                        onLongPress: () {
                          _toggleSelection(preset.id);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}