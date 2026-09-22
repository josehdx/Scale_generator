import 'package:flutter/material.dart';
import '../scale_engine.dart';

class InteractiveFretboard extends StatelessWidget {
  final ScaleEngine engine;
  final String selectedKey;
  final String selectedScale;
  final int startFret;
  final String selectedTuning;
  final int? activeString;
  final int? activeFret;
  final int? previewString;
  final int? previewFret;
  final String? previewKey;
  final String? previewScale;
  final String? previewTuning;
  final bool? isAccent;
  final ScrollController? scrollController;
  final Function(String newKey, int fret) onNoteTapped;

  const InteractiveFretboard({
    super.key,
    required this.engine,
    required this.selectedKey,
    required this.selectedScale,
    required this.startFret,
    required this.selectedTuning,
    this.activeString,
    this.activeFret,
    this.previewString,
    this.previewFret,
    this.previewKey,
    this.previewScale,
    this.previewTuning,
    this.isAccent,
    this.scrollController,
    required this.onNoteTapped,
  });

  @override
  Widget build(BuildContext context) {
    engine.setTuning(previewTuning ?? selectedTuning);
    String effectiveKey = previewKey ?? selectedKey;
    String effectiveScale = previewScale ?? selectedScale;
    List<int> scaleFormula = engine.scaleFormulas[effectiveScale] ?? [];
    int rootPitch = engine.noteMap[effectiveKey] ?? 0;

    return Container(
      height: 225, // Fixed height constraint ensures touch gestures are routed properly
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
                  
                  bool isInScale = scaleFormula.contains(interval);
                  bool isRoot = interval == 0;
                  bool isActive = (activeString == stringNum && activeFret == fretNum);
                  bool isPreview = (previewString == stringNum && previewFret == fretNum);
                  bool isThisAccent = isAccent ?? false;

                  String noteName = engine.noteMap.entries
                      .firstWhere((e) => e.value == notePitch,
                          orElse: () => const MapEntry("", -1))
                      .key;

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
                    noteColor = isThisAccent ? Colors.orangeAccent : Colors.greenAccent;
                    textColor = Colors.black;
                  }
                  if (isPreview) {
                    noteColor = isThisAccent ? Colors.pinkAccent : Colors.purpleAccent.shade200;
                    textColor = Colors.white;
                  }

                  return GestureDetector(
                    onTap: () {
                      onNoteTapped(noteName, fretNum);
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
                        child: Container(
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
}