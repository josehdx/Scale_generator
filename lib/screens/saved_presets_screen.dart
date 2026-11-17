import 'package:flutter/material.dart';
import '../models/lick_preset.dart';
import '../models/preset_sanitizer.dart';
import '../services/preset_storage_service.dart';

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
  final void Function(String, int)? onUpdateTempo;
  final PresetStorageService? storageService;
  final String initialSortBy;
  final bool initialSortAscending;

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
    this.onUpdateTempo,
    this.storageService,
    this.initialSortBy = 'Creation Date',
    this.initialSortAscending = true,
  });

  @override
  State<SavedPresetsScreen> createState() => _SavedPresetsScreenState();
}

class _SavedPresetsScreenState extends State<SavedPresetsScreen> with AutomaticKeepAliveClientMixin {
  final Set<String> _selectedIds = {};
  final Map<String, GlobalKey> _itemKeys = {};
  final Map<String, bool> _validationCache = {};
  late PresetStorageService _storageService;
  late String _sortBy;
  late bool _isAscending;

  List<LickPreset> get _sortedPresets {
    return PresetStorageService.sortPresets(
      widget.savedPresets,
      sortBy: _sortBy,
      ascending: _isAscending,
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.initialSortBy;
    _isAscending = widget.initialSortAscending;
    _storageService = widget.storageService ?? PresetStorageService();
    _rebuildValidationCache();
  }

  @override
  void didUpdateWidget(covariant SavedPresetsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storageService != null) {
      _storageService = widget.storageService!;
    }
    
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
      final list = _sortedPresets;
      if (widget.activePreviewId != null) {
        final preset = list.firstWhere(
            (p) => p.id == widget.activePreviewId,
            orElse: () => list.first);
        widget.onPlayPreview(preset);
      } else if (list.isNotEmpty) {
        widget.onPlayPreview(list.first);
      }
    }
  }

  void _handleNext() {
    final list = _sortedPresets;
    if (list.isEmpty) return;
    int idx = list.indexWhere((p) => p.id == widget.activePreviewId);
    if (idx == -1 || idx == list.length - 1) {
      widget.onPlayPreview(list.first);
    } else {
      widget.onPlayPreview(list[idx + 1]);
    }
  }

  void _handlePrev() {
    final list = _sortedPresets;
    if (list.isEmpty) return;
    int idx = list.indexWhere((p) => p.id == widget.activePreviewId);
    if (idx == -1 || idx == 0) {
      widget.onPlayPreview(list.last);
    } else {
      widget.onPlayPreview(list[idx - 1]);
    }
  }

  /// Deleting presets cannot be undone, so ask first.
  Future<void> _confirmDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ids.length == 1 ? 'Delete this preset?' : 'Delete ${ids.length} presets?'),
        content: const Text('This cannot be undone. Export them first if you want a backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.onDeletePresets(ids);
      _clearSelection();
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

  Future<void> _updatePresetTempo(LickPreset preset, int newTempo) async {
    if (preset.tempo == newTempo) return;

    final index = widget.savedPresets.indexWhere((p) => p.id == preset.id);
    if (index != -1) {
      final updated = widget.savedPresets[index].copyWith(tempo: newTempo);
      setState(() {
        widget.savedPresets[index] = updated;
      });
      await _storageService.savePresets(widget.savedPresets);
      widget.onUpdateTempo?.call(preset.id, newTempo);
    } else {
      await _storageService.updatePresetTempo(preset.id, newTempo);
      widget.onUpdateTempo?.call(preset.id, newTempo);
    }
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
                      value: _selectedIds.length == _sortedPresets.length && _sortedPresets.isNotEmpty,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedIds.addAll(_sortedPresets.map((e) => e.id));
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
                        final toExport = _sortedPresets
                            .where((p) => _selectedIds.contains(p.id))
                            .toList();
                        widget.onExportPresets(toExport);
                        _clearSelection();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      tooltip: "Delete Selected",
                      onPressed: () => _confirmDelete(_selectedIds.toList()),
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
                          onPressed: () => widget.onExportPresets(_sortedPresets),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          color: Colors.black12,
          child: Row(
            children: [
              const Icon(Icons.sort, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text("Sort by:", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                key: const Key('sort_presets_dropdown'),
                value: _sortBy,
                dropdownColor: Colors.grey.shade900,
                underline: Container(height: 1, color: Colors.white24),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(
                    value: 'Creation Date',
                    child: Text('Creation Date'),
                  ),
                  DropdownMenuItem(
                    value: 'Name',
                    child: Text('Name'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _sortBy = val;
                    });
                  }
                },
              ),
              const Spacer(),
              IconButton(
                key: const Key('sort_order_toggle_button'),
                icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 18, color: Colors.white70),
                tooltip: _isAscending ? 'Ascending' : 'Descending',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _isAscending = !_isAscending;
                  });
                },
              ),
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
                  itemCount: _sortedPresets.length,
                  onReorder: (oldIndex, newIndex) {
                    final sorted = _sortedPresets;
                    if (newIndex > oldIndex) newIndex--;
                    final moved = sorted[oldIndex];
                    final origOld = widget.savedPresets.indexWhere((p) => p.id == moved.id);
                    int origNew;
                    if (newIndex < sorted.length) {
                      origNew = widget.savedPresets.indexWhere((p) => p.id == sorted[newIndex].id);
                    } else {
                      origNew = widget.savedPresets.length - 1;
                    }
                    if (origOld != -1 && origNew != -1) {
                      widget.onReorderPresets(origOld, origNew);
                    }
                  },
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final preset = _sortedPresets[index];
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
                                  triggerMode: TooltipTriggerMode.tap,
                                  message: "The accent pattern did not match this lick's length. "
                                      "It is adjusted automatically when you play or load the preset - nothing to fix.",
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.info_outline, size: 18, color: Colors.amberAccent),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    const Text("Tempo: ", style: TextStyle(color: Colors.white70, fontSize: 13)),
                                    InlineTempoEditor(
                                      key: ValueKey('tempo_editor_${preset.id}'),
                                      tempo: preset.tempo,
                                      onChanged: (newTempo) => _updatePresetTempo(preset, newTempo),
                                    ),
                                    const Text(" BPM | ", style: TextStyle(color: Colors.white70, fontSize: 13)),
                                    Text("System: ${preset.system}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Generated: ${preset.createdAt.toString().split('.')[0]}",
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
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
                                    if (value == 'delete') _confirmDelete([preset.id]);
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
                                child: const Tooltip(
                                  message: 'Drag to reorder',
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_handle, color: Colors.white54, size: 28),
                                  ),
                                ),
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

/// An inline editor for tempo with a digital keyboard input and increment/decrement arrow buttons.
class InlineTempoEditor extends StatefulWidget {
  final int tempo;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  const InlineTempoEditor({
    super.key,
    required this.tempo,
    required this.onChanged,
    this.min = 1,
    this.max = 999,
  });

  @override
  State<InlineTempoEditor> createState() => _InlineTempoEditorState();
}

class _InlineTempoEditorState extends State<InlineTempoEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.tempo.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant InlineTempoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tempo != widget.tempo && !_focusNode.hasFocus) {
      _controller.text = widget.tempo.toString();
    }
  }

  @override
  void dispose() {
    if (_focusNode.hasFocus) {
      _commitValue();
    }
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitValue();
    }
  }

  void _commitValue() {
    final int? parsed = int.tryParse(_controller.text);
    if (parsed != null && parsed > 0) {
      final clamped = parsed.clamp(widget.min, widget.max);
      _controller.text = clamped.toString();
      if (clamped != widget.tempo) {
        widget.onChanged(clamped);
      }
    } else {
      _controller.text = widget.tempo.toString();
    }
  }

  void _adjustTempo(int delta) {
    if (_focusNode.hasFocus) {
      _focusNode.removeListener(_handleFocusChange);
      _focusNode.unfocus();
      _focusNode.addListener(_handleFocusChange);
    }
    final int current = int.tryParse(_controller.text) ?? widget.tempo;
    final int next = (current + delta).clamp(widget.min, widget.max);
    _controller.text = next.toString();
    if (next != widget.tempo) {
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: 'Decrease tempo',
          child: IconButton(
            key: const Key('tempo_decrement_button'),
            icon: const Icon(Icons.arrow_drop_down, size: 22, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
            splashRadius: 14,
            tooltip: 'Decrease tempo',
            onPressed: () => _adjustTempo(-1),
          ),
        ),
        SizedBox(
          width: 44,
          height: 28,
          child: TextFormField(
            key: const Key('tempo_text_field'),
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade600, width: 0.8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade600, width: 0.8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Colors.greenAccent, width: 1.2),
              ),
            ),
            onTapOutside: (_) => _focusNode.unfocus(),
            onFieldSubmitted: (_) => _focusNode.unfocus(),
          ),
        ),
        Semantics(
          button: true,
          label: 'Increase tempo',
          child: IconButton(
            key: const Key('tempo_increment_button'),
            icon: const Icon(Icons.arrow_drop_up, size: 22, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
            splashRadius: 14,
            tooltip: 'Increase tempo',
            onPressed: () => _adjustTempo(1),
          ),
        ),
      ],
    );
  }
}
