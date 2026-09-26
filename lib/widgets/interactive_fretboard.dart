import 'package:flutter/material.dart';
import '../scale_engine.dart';

class InteractiveFretboard extends StatelessWidget {
  final ScaleEngine engine;
  final String selectedKey;
  final String selectedScale;
  final int startFret;
  final String selectedTuning;
  final ValueNotifier<Map<String, dynamic>?>? activeNoteNotifier; // [FIX] Isolated Value Notifier Prop
  final bool isManualMode;
  final ScrollController? scrollController;
  final Function(String newKey, int stringNum, int fretNum) onNoteTapped;

  const InteractiveFretboard({
    super.key,
    required this.engine,
    required this.selectedKey,
    required this.selectedScale,
    required this.startFret,
    required this.selectedTuning,
    this.activeNoteNotifier,
    this.isManualMode = false,
    this.scrollController,
    required this.onNoteTapped,
  });

  @override
  Widget build(BuildContext context) {
    engine.setTuning(selectedTuning);
    List<int> scaleFormula = engine.scaleFormulas[selectedScale] ?? [];
    int rootPitch = engine.noteMap[selectedKey] ?? 0;

    return Container(
      height: 225, 
      decoration: BoxDecoration(
        color: Colors.brown.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade700, width: 2),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 6 GUITAR STRINGS
            ...List.generate(6, (stringIndex) {
              int stringNum = stringIndex + 1; 
              int openPitch = engine.openStrings[stringNum]!;

              return Row(
                children: List.generate(25, (fretNum) {
                  int notePitch = (openPitch + fretNum) % 12;
                  int interval = (notePitch - rootPitch + 12) % 12;
                  
                  bool isInScale = isManualMode ? true : scaleFormula.contains(interval);
                  bool isRoot = isManualMode ? false : interval == 0;

                  String noteName = engine.noteMap.entries
                      .firstWhere((e) => e.value == notePitch,
                          orElse: () => const MapEntry("", -1))
                      .key;

                  // [FIX] Push ValueListenableBuilder down to individual cells for O(1) repaints
                  return GestureDetector(
                    onTap: () {
                      onNoteTapped(noteName, stringNum, fretNum);
                    },
                    child: Container(
                      width: fretNum == 0 ? 36 : 46,
                      height: 32,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: Colors.grey.shade400,
                            width: fretNum == 0 ? 4 : 2,
                          ),
                          bottom: BorderSide(
                            color: Colors.grey.shade600,
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Center(
                        child: activeNoteNotifier == null 
                          ? _buildFretNote(isInScale, isRoot, false, false, false, noteName)
                          : ValueListenableBuilder<Map<String, dynamic>?>(
                              valueListenable: activeNoteNotifier!,
                              builder: (context, noteData, _) {
                                bool isActive = false;
                                bool isPreview = false;
                                bool isThisAccent = false;

                                if (noteData != null) {
                                  bool isPreviewMode = noteData['isPreview'] as bool;
                                  
                                  int? activeStr = isPreviewMode ? null : noteData['string'];
                                  int? activeFrt = isPreviewMode ? null : noteData['fret'];
                                  int? prevStr = isPreviewMode ? noteData['string'] : null;
                                  int? prevFrt = isPreviewMode ? noteData['fret'] : null;

                                  isActive = (activeStr == stringNum && activeFrt == fretNum);
                                  isPreview = (prevStr == stringNum && prevFrt == fretNum);
                                  isThisAccent = noteData['isAccent'] ?? false;
                                }

                                return _buildFretNote(isInScale, isRoot, isActive, isPreview, isThisAccent, noteName);
                              },
                            ),
                      ),
                    ),
                  );
                }),
              );
            }),

            // FRET NUMBER REFERENCE ROW (0 to 24)
            Container(
              color: Colors.black45,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: List.generate(25, (fretNum) {
                  bool isMarker = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fretNum);
                  
                  return Container(
                    width: fretNum == 0 ? 36 : 46,
                    alignment: Alignment.center,
                    child: Text(
                      fretNum == 0 ? "Nut" : "$fretNum",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isMarker ? FontWeight.bold : FontWeight.normal,
                        color: isMarker ? Colors.amberAccent : Colors.grey.shade400,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFretNote(bool isInScale, bool isRoot, bool isActive, bool isPreview, bool isAccent, String noteName) {
    Color noteColor = Colors.grey.shade800;
    Color textColor = Colors.white38;
    
    if (isInScale) {
      noteColor = Colors.blueAccent;
      textColor = Colors.white;
    }
    if (isRoot) {
      noteColor = Colors.redAccent;
      textColor = Colors.white;
    }
    if (isActive) {
      noteColor = isAccent ? Colors.orangeAccent : Colors.greenAccent;
      textColor = Colors.black;
    }
    if (isPreview) {
      noteColor = isAccent ? Colors.pinkAccent : Colors.purpleAccent.shade200;
      textColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: noteColor,
        shape: BoxShape.circle,
        boxShadow: (isActive || isPreview)
            ? [BoxShadow(color: noteColor, blurRadius: 6)]
            : [],
      ),
      child: Text(
        noteName,
        style: TextStyle(
          fontSize: 10,
          fontWeight: (isInScale || isRoot || isActive || isPreview)
              ? FontWeight.bold
              : FontWeight.normal,
          color: textColor,
        ),
      ),
    );
  }
}