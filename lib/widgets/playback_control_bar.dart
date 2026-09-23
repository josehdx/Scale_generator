import 'package:flutter/material.dart';
import '../models/gp_track.dart';

/// A reusable playback toolbar used by both the main Tab Studio and the GP Viewer.
///
/// All GP-Viewer-specific parameters ([isPaused], [gpLoopMode], [onCycleLoopMode])
/// are optional and default to inert values so the main-studio call site requires
/// zero changes.
class PlaybackControlBar extends StatelessWidget {
  // ── Core params (used by main studio + GP viewer) ─────────────────────────
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

  // ── GP Viewer extensions (all optional, backward-compatible) ──────────────

  /// True when playback has been paused mid-track (position preserved).
  final bool isPaused;

  /// When non-null the bar renders in GP-viewer mode:
  /// • Play/Pause/Resume button with pause semantics.
  /// • 3-state loop icon (off → all → selection).
  final LoopMode? gpLoopMode;

  /// Callback that cycles [gpLoopMode] through off → all → selection → off.
  /// Required when [gpLoopMode] is non-null.
  final VoidCallback? onCycleLoopMode;

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
  });

  // ── Helpers ───────────────────────────────────────────────────────────────

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
        return 'Loop: OFF  (tap → Loop All)';
      case LoopMode.all:
        return 'Loop: ALL  (tap → Loop Selection)';
      case LoopMode.selection:
        return 'Loop: SELECTION  (tap → Loop Off)';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool gpMode = gpLoopMode != null;

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
                // ── Play / Pause / Resume / Stop ────────────────────────────
                if (isPlaying)
                  // GP mode → Pause; legacy mode → Stop
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
                    label: Text(hasSelection ? 'Play Selection' : 'Play'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),

                const SizedBox(width: 4),

                // ── Stop (GP mode only — separate from Pause) ───────────────
                if (gpMode)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    color: Colors.redAccent,
                    tooltip: 'Stop & Reset',
                    onPressed: onStop,
                  ),

                const SizedBox(width: 4),

                // ── Loop toggle ──────────────────────────────────────────────
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

                // ── Studio-only actions (hidden in GP mode) ──────────────────
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

          // ── Loop mode label (GP mode) ──────────────────────────────────────
          if (gpMode && gpLoopMode != LoopMode.off)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                gpLoopMode == LoopMode.all ? '⟳  Loop All' : '⟳  Loop Selection',
                style: TextStyle(
                  fontSize: 10,
                  color: _loopColor(gpLoopMode!),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // ── Selection range indicator ──────────────────────────────────────
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Selected Notes: ${selectionStart + 1} – ${selectionEnd + 1}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.cyanAccent),
                  ),
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