import 'package:flutter/material.dart';
import '../../models/gp_beat.dart';
import '../interactive_tab_display.dart';

class TabOutputSection extends StatelessWidget {
  final List<GpBeat> currentSequence;
  final String generatedTab;
  final String autoTimeSignature;
  final ValueNotifier<Map<String, dynamic>?> activeNoteNotifier;
  final int notesPerMeasure;
  final String rhythmStr;
  final int measuresPerLine;
  final int selectionStart;
  final int selectionEnd;
  final String selectedTuning;
  final Function(int) onBeatTapped;

  const TabOutputSection({
    super.key,
    required this.currentSequence,
    required this.generatedTab,
    required this.autoTimeSignature,
    required this.activeNoteNotifier,
    required this.notesPerMeasure,
    required this.rhythmStr,
    required this.measuresPerLine,
    required this.selectionStart,
    required this.selectionEnd,
    required this.selectedTuning,
    required this.onBeatTapped,
  });

  @override
  Widget build(BuildContext context) {
    if (currentSequence.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
        width: double.infinity,
        child: Text(generatedTab, style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
      );
    }
    
    return Container(
      constraints: const BoxConstraints(maxHeight: 350),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade800)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: Colors.blueGrey.shade800)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Time Signature: $autoTimeSignature (Driven Automatically)", style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                const Icon(Icons.lock_outline, size: 12, color: Colors.grey),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: activeNoteNotifier,
                builder: (context, noteData, child) {
                  int playingIdx = -1;
                  if (noteData != null && !noteData['isPreview']) playingIdx = noteData['index'];
                  
                  return InteractiveTabDisplay(
                    sequence: currentSequence,
                    notesPerMeasure: notesPerMeasure,
                    measuresPerLine: measuresPerLine <= 0 ? 999 : measuresPerLine,
                    currentPlayingIndex: playingIdx,
                    selectionStart: selectionStart,
                    selectionEnd: selectionEnd,
                    tuningStr: selectedTuning,
                    onBeatTapped: onBeatTapped,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}