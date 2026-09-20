import 'package:flutter/material.dart';

class PlaybackControlBar extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isPlaying)
                  ElevatedButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: (isMidiReady && hasSequence) ? onPlay : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(hasSelection ? "Play Selection" : "Play Lick"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.repeat, color: isLooping ? Colors.amberAccent : Colors.grey),
                  tooltip: isLooping ? 'Looping ON' : 'Looping OFF',
                  onPressed: onToggleLoop,
                ),
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
            ),
          ),
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Selected Notes: ${selectionStart + 1} to ${selectionEnd + 1}", 
                      style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onClearSelection,
                    child: const Icon(Icons.cancel, size: 16, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}