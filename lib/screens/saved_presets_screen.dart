import 'package:flutter/material.dart';
import '../models/lick_preset.dart';
import '../models/preset_sanitizer.dart';

class SavedPresetsScreen extends StatefulWidget {
  final List<LickPreset> savedPresets;
  final String? activePreviewId;
  final bool isPreviewPlaying;
  final bool isPreviewLooping;
  final Function(LickPreset) onPlayPreview;
  final VoidCallback onStopPreview;
  final VoidCallback onTogglePreviewLoop;
  final Function(LickPreset) onLoadPreset;
  final Function(List<String>) onDeletePresets;
  final Function(String, String) onRenamePreset;
  final Function(List<LickPreset>) onExportPresets;
  final Function(int, int) onReorderPresets;
  final VoidCallback onImport;

  const SavedPresetsScreen({
    super.key,
    required this.savedPresets,
    this.activePreviewId,
    required this.isPreviewPlaying,
    required this.isPreviewLooping,
    required this.onPlayPreview,
    required this.onStopPreview,
    required this.onTogglePreviewLoop,
    required this.onLoadPreset,
    required this.onDeletePresets,
    required this.onRenamePreset,
    required this.onExportPresets,
    required this.onReorderPresets,
    required this.onImport,
  });

  @override
  State<SavedPresetsScreen> createState() => _SavedPresetsScreenState();
}

class _SavedPresetsScreenState extends State<SavedPresetsScreen> with AutomaticKeepAliveClientMixin {
  final Set<String> _selectedIds = {};
  final Map<String, GlobalKey> _itemKeys = {};
  final Map<String, bool> _validationCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _rebuildValidationCache();
  }

  @override
  void didUpdateWidget(covariant SavedPresetsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.savedPresets != oldWidget.savedPresets) {
      _rebuildValidationCache();
      
      // [FIX]: Memory Leak Resolution. Clear orphaned GlobalKeys from map.
      final currentIds = widget.savedPresets.map((p) => p.id).toSet();
      _itemKeys.removeWhere((key, _) => !currentIds.contains(key));
    }

    if (widget.activePreviewId != oldWidget.activePreviewId && widget.activePreviewId != null) {
      _scrollToActivePreview();
    }
  }

  void _rebuildValidationCache() {
    _validationCache.clear();
    for (var preset in widget.savedPresets) {
      final (_, issues) = PresetSanitizer.validateAndSanitize(preset);
      _validationCache[preset.id] = issues.isNotEmpty;
    }
  }

  void _scrollToActivePreview() {
    final key = _itemKeys[widget.activePreviewId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

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

  void _handlePlayStop() {
    if (widget.isPreviewPlaying) {
      widget.onStopPreview();
    } else {
      if (widget.activePreviewId != null) {
        final preset = widget.savedPresets.firstWhere(
            (p) => p.id == widget.activePreviewId,
            orElse: () => widget.savedPresets.first);
        widget.onPlayPreview(preset);
      } else if (widget.savedPresets.isNotEmpty) {
        widget.onPlayPreview(widget.savedPresets.first);
      }
    }
  }

  void _handleNext() {
    if (widget.savedPresets.isEmpty) return;
    int idx = widget.savedPresets.indexWhere((p) => p.id == widget.activePreviewId);
    if (idx == -1 || idx == widget.savedPresets.length - 1) {
      widget.onPlayPreview(widget.savedPresets.first);
    } else {
      widget.onPlayPreview(widget.savedPresets[idx + 1]);
    }
  }

  void _handlePrev() {
    if (widget.savedPresets.isEmpty) return;
    int idx = widget.savedPresets.indexWhere((p) => p.id == widget.activePreviewId);
    if (idx == -1 || idx == 0) {
      widget.onPlayPreview(widget.savedPresets.last);
    } else {
      widget.onPlayPreview(widget.savedPresets[idx - 1]);
    }
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
    super.build(context);
    bool hasSelection = _selectedIds.isNotEmpty;

    return Column(
      children: [
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
        if (!hasSelection && widget.savedPresets.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
            color: Colors.black26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 28),
                  tooltip: 'Previous Preset',
                  onPressed: _handlePrev,
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: Icon(widget.isPreviewPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(widget.isPreviewPlaying ? "Stop Preview" : "Play Preview"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isPreviewPlaying ? Colors.redAccent : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: _handlePlayStop,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 28),
                  tooltip: 'Next Preset',
                  onPressed: _handleNext,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.repeat,
                    size: 24,
                    color: widget.isPreviewLooping ? Colors.amberAccent : Colors.white38,
                  ),
                  tooltip: 'Toggle Loop',
                  onPressed: widget.onTogglePreviewLoop,
                ),
              ],
            ),
          ),
        Expanded(
          child: widget.savedPresets.isEmpty
              ? const Center(
                  child: Text(
                    "No presets saved yet.\nGenerate a lick and press the Bookmark icon!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: widget.savedPresets.length,
                  onReorder: widget.onReorderPresets,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final preset = widget.savedPresets[index];
                    _itemKeys.putIfAbsent(preset.id, () => GlobalKey());
                    
                    bool isSelected = _selectedIds.contains(preset.id);
                    bool isActive = widget.activePreviewId == preset.id;
                    bool isPlayingThis = isActive && widget.isPreviewPlaying;
                    
                    final bool hasMisalignment = _validationCache[preset.id] ?? false;
                    
                    return Card(
                      key: ValueKey(preset.id),
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isActive ? Colors.green.withOpacity(0.5) : Colors.transparent,
                          width: 1.0,
                        ),
                      ),
                      color: isSelected
                          ? Colors.blue.withOpacity(0.2)
                          : (isPlayingThis ? Colors.green.withOpacity(0.15) : (isActive ? Colors.green.withOpacity(0.05) : Colors.grey.shade900)),
                      child: Container(
                        key: _itemKeys[preset.id],
                        child: ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleSelection(preset.id),
                              ),
                              CircleAvatar(
                                backgroundColor: isPlayingThis ? Colors.green : (isActive ? Colors.teal : Colors.blueAccent),
                                child: Icon(isPlayingThis ? Icons.volume_up : (isActive ? Icons.play_arrow : Icons.music_note), color: Colors.white),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  preset.name, 
                                  style: const TextStyle(fontWeight: FontWeight.bold), 
                                  maxLines: 3, 
                                  overflow: TextOverflow.ellipsis
                                )
                              ),
                              if (hasMisalignment) ...[
                                const SizedBox(width: 8),
                                const Tooltip(
                                  message: "Sequence length mismatch detected.",
                                  child: Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amberAccent),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text("Tempo: ${preset.tempo} BPM | System: ${preset.system}\nGenerated: ${preset.createdAt.toString().split('.')[0]}"),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPlayingThis)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8.0),
                                  child: Icon(Icons.equalizer, color: Colors.greenAccent, size: 20),
                                ),
                              if (!hasSelection)
                                PopupMenuButton<String>(
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
                              const SizedBox(width: 8),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle, color: Colors.white54, size: 28),
                              ),
                            ],
                          ),
                          onTap: () {
                            if (hasSelection) {
                              _toggleSelection(preset.id);
                            } else {
                              widget.onPlayPreview(preset);
                            }
                          },
                          onLongPress: () {
                            _toggleSelection(preset.id);
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}