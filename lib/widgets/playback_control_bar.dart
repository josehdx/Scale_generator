import 'package:flutter/material.dart';
import '../models/gp_track.dart';

/// A reusable playback toolbar used by both the main Tab Studio and the GP Viewer.
/// All GP-Viewer-specific parameters ([isPaused], [gpLoopMode], [onCycleLoopMode])
/// are optional and default to inert values so the main-studio call site requires
/// zero changes.
class PlaybackControlBar extends StatelessWidget {
  // --- Core params (used by main studio + GP viewer) ---
  final bool isPlaying;
  final bool isMidiReady;
  final bool isLooping;
  final bool hasSequence;
  final bool hasSelection;
  final int selectionStart;
  final int selectionEnd;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onToggleLoop;
  final VoidCallback onSave;
  final VoidCallback onCopy;
  final VoidCallback onClearSelection;

  // --- GP Viewer extensions (all optional, backward-compatible) ---
  /// True when playback has been paused mid-track (position preserved).
  final bool isPaused;
  /// When non-null the bar renders in GP-viewer mode:
  /// - Play/Pause/Resume button with pause semantics.
  /// - 3-state loop icon (off -> all -> selection).
  final LoopMode? gpLoopMode;
  /// Callback that cycles [gpLoopMode] through off -> all -> selection -> off.
  /// Required when [gpLoopMode] is non-null.
  final VoidCallback? onCycleLoopMode;
  /// Rewinds playback position to note 0.
  final VoidCallback? onRewind;
  /// Current playback speed multiplier (e.g. 1.0).
  final double? speedMultiplier;
  /// Callback to change playback speed multiplier.
  final ValueChanged<double>? onSpeedChanged;
  /// Number of dynamic rests inserted at selection / end.
  final int? endRests;
  /// Callback to adjust rest count.
  final ValueChanged<int>? onEndRestsChanged;

  const PlaybackControlBar({
    super.key,
    required this.isPlaying,
    required this.isMidiReady,
    required this.isLooping,
    required this.hasSequence,
    required this.hasSelection,
    required this.selectionStart,
    required this.selectionEnd,
    required this.onPlay,
    required this.onStop,
    required this.onToggleLoop,
    required this.onSave,
    required this.onCopy,
    required this.onClearSelection,
    // GP-viewer extensions
    this.isPaused = false,
    this.gpLoopMode,
    this.onCycleLoopMode,
    this.onRewind,
    this.speedMultiplier,
    this.onSpeedChanged,
    this.endRests,
    this.onEndRestsChanged,
  });

  // --- Helpers ---
  /// Icon for the current [LoopMode].
  IconData _loopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.all:
        return Icons.repeat;
      case LoopMode.selection:
        return Icons.repeat_one;
    }
  }

  /// Accent colour for the loop icon based on [LoopMode].
  Color _loopColor(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Colors.grey;
      case LoopMode.all:
        return Colors.amberAccent;
      case LoopMode.selection:
        return Colors.cyanAccent;
    }
  }

  /// Tooltip string for the current [LoopMode].
  String _loopTooltip(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return 'Loop: OFF  (tap = Loop All)';
      case LoopMode.all:
        return 'Loop: ALL  (tap = Loop Selection)';
      case LoopMode.selection:
        return 'Loop: SELECTION  (tap = Loop Off)';
    }
  }

  // --- Build ---
  void _showSpeedDialog(BuildContext context) {
    if (onSpeedChanged == null) return;
    double current = speedMultiplier ?? 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Playback Speed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            final TextEditingController ctrl = TextEditingController(text: current.toStringAsFixed(2));
                            showDialog(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                backgroundColor: Colors.grey.shade900,
                                title: const Text('Set Speed (0.10 - 2.00)', style: TextStyle(color: Colors.white, fontSize: 16)),
                                content: TextField(
                                  controller: ctrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                                  ),
                                  autofocus: true,
                                  onSubmitted: (val) {
                                    double? parsed = double.tryParse(val);
                                    if (parsed != null) {
                                      double clamped = ((parsed * 100).round() / 100.0).clamp(0.1, 2.0);
                                      setModalState(() => current = clamped);
                                      onSpeedChanged!(clamped);
                                    }
                                    Navigator.pop(dialogCtx);
                                  },
                                ),
                                actions: [
                                  TextButton(
                                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                    onPressed: () => Navigator.pop(dialogCtx)
                                  ),
                                  ElevatedButton(
                                    child: const Text('Set'),
                                    onPressed: () {
                                      double? parsed = double.tryParse(ctrl.text);
                                      if (parsed != null) {
                                        double clamped = ((parsed * 100).round() / 100.0).clamp(0.1, 2.0);
                                        setModalState(() => current = clamped);
                                        onSpeedChanged!(clamped);
                                      }
                                      Navigator.pop(dialogCtx);
                                    }
                                  )
                                ],
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${current.toStringAsFixed(2)}x',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                          onPressed: current > 0.10
                              ? () {
                                  final next = ((current - 0.01) * 100).round() / 100.0;
                                  final clamped = next.clamp(0.1, 2.0);
                                  setModalState(() => current = clamped);
                                  onSpeedChanged!(clamped);
                                }
                              : null,
                        ),
                        Expanded(
                          child: Slider(
                            value: current.clamp(0.1, 2.0),
                            min: 0.1,
                            max: 2.0,
                            divisions: 190,
                            label: '${current.toStringAsFixed(2)}x',
                            activeColor: Colors.blueAccent,
                            inactiveColor: Colors.grey.shade800,
                            onChanged: (val) {
                              final snapped = ((val * 100).round() / 100.0).clamp(0.1, 2.0);
                              setModalState(() => current = snapped);
                              onSpeedChanged!(snapped);
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                          onPressed: current < 2.00
                              ? () {
                                  final next = ((current + 0.01) * 100).round() / 100.0;
                                  final clamped = next.clamp(0.1, 2.0);
                                  setModalState(() => current = clamped);
                                  onSpeedChanged!(clamped);
                                }
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((preset) {
                        final bool isSelected = (current - preset).abs() < 0.005;
                        return ChoiceChip(
                          label: Text(
                            '${preset}x',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : Colors.grey.shade300,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: Colors.blueAccent,
                          backgroundColor: Colors.grey.shade800,
                          onSelected: (_) {
                            setModalState(() => current = preset);
                            onSpeedChanged!(preset);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool gpMode = gpLoopMode != null;
    
    String playLabel;
    if (hasSelection) {
      if (selectionStart == selectionEnd) {
        playLabel = 'Play from here';
      } else {
        playLabel = 'Play selected group';
      }
    } else {
      playLabel = 'Play';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // --- Rewind Button (reset to note 0, double-tap to deselect) ---
                if (onRewind != null) ...[
                  Tooltip(
                    message: 'Rewind to Beginning (Double-tap to clear selection)',
                    child: InkWell(
                      onTap: onRewind,
                      onDoubleTap: onClearSelection,
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        child: Icon(Icons.first_page, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                // --- Play / Pause / Resume / Stop ---
                if (isPlaying)
                  // GP mode = Pause; legacy mode = Stop
                  ElevatedButton.icon(
                    onPressed: gpMode ? onPlay : onStop,
                    icon: Icon(gpMode ? Icons.pause : Icons.stop),
                    label: Text(gpMode ? 'Pause' : 'Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  )
                else if (gpMode && isPaused)
                  ElevatedButton.icon(
                    onPressed: (isMidiReady && hasSequence) ? onPlay : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: (isMidiReady && hasSequence) ? onPlay : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(playLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                const SizedBox(width: 4),

                // --- Stop (GP mode only = separate from Pause) ---
                if (gpMode)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    color: Colors.redAccent,
                    tooltip: 'Stop & Reset',
                    onPressed: onStop,
                  ),
                const SizedBox(width: 4),

                // --- Loop toggle ---
                if (gpMode)
                  IconButton(
                    icon: Icon(_loopIcon(gpLoopMode!),
                        color: _loopColor(gpLoopMode!)),
                    tooltip: _loopTooltip(gpLoopMode!),
                    onPressed: onCycleLoopMode ?? onToggleLoop,
                  )
                else
                  IconButton(
                    icon: Icon(Icons.repeat,
                        color: isLooping ? Colors.amberAccent : Colors.grey),
                    tooltip: isLooping ? 'Looping ON' : 'Looping OFF',
                    onPressed: onToggleLoop,
                  ),

                // --- Speed Multiplier Button ---
                if (speedMultiplier != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _showSpeedDialog(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (speedMultiplier != 1.0)
                              ? Colors.blueAccent
                              : Colors.grey.shade700,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed, size: 14, color: Colors.blueAccent),
                          const SizedBox(width: 4),
                          Text(
                            '${(speedMultiplier ?? 1.0).toStringAsFixed(2)}x',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: (speedMultiplier != 1.0)
                                  ? Colors.blueAccent
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // --- Studio-only actions (hidden in GP mode) ---
                if (!gpMode) ...[
                  IconButton(
                    icon: const Icon(Icons.bookmark_add),
                    tooltip: 'Save Preset',
                    onPressed: onSave,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy Output',
                    onPressed: onCopy,
                  ),
                ],
              ],
            ),
          ),

          // --- Loop mode label (GP mode) ---
          if (gpMode && gpLoopMode != LoopMode.off)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                gpLoopMode == LoopMode.all ? '  Loop All' : '  Loop Selection',
                style: TextStyle(
                  fontSize: 10,
                  color: _loopColor(gpLoopMode!),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // --- Selection range indicator & Rest controls ---
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Selected Notes: ${selectionStart + 1} - ${selectionEnd + 1}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.cyanAccent),
                  ),
                  if (onEndRestsChanged != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Rests: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          GestureDetector(
                            onTap: (endRests ?? 0) > 0
                                ? () => onEndRestsChanged!((endRests ?? 0) - 1)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Icon(
                                Icons.remove_circle_outline,
                                size: 16,
                                color: (endRests ?? 0) > 0 ? Colors.white70 : Colors.white24,
                              ),
                            ),
                          ),
                          Text(
                            '${endRests ?? 0}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => onEndRestsChanged!((endRests ?? 0) + 1),
                            child: const Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Icon(
                                Icons.add_circle_outline,
                                size: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onClearSelection,
                    child: const Icon(Icons.cancel,
                        size: 16, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}