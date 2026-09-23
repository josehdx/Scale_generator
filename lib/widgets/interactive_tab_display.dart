import 'dart:math';
import 'package:flutter/material.dart';

class InteractiveTabDisplay extends StatefulWidget {
  final List<List<int>> sequence;
  final int notesPerMeasure;
  final int measuresPerLine;
  final int currentPlayingIndex;
  final int selectionStart;
  final int selectionEnd;
  final String tuningStr;
  final Function(int index) onBeatTapped;

  const InteractiveTabDisplay({
    super.key,
    required this.sequence,
    required this.notesPerMeasure,
    required this.measuresPerLine,
    required this.currentPlayingIndex,
    required this.selectionStart,
    required this.selectionEnd,
    required this.tuningStr,
    required this.onBeatTapped,
  });

  @override
  State<InteractiveTabDisplay> createState() => _InteractiveTabDisplayState();
}

class _InteractiveTabDisplayState extends State<InteractiveTabDisplay> {
  final ScrollController _verticalController = ScrollController();
  final List<ScrollController> _horizontalControllers = [];

  @override
  void dispose() {
    _verticalController.dispose();
    for (var controller in _horizontalControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InteractiveTabDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    int notesPerSystem = widget.notesPerMeasure * widget.measuresPerLine;
    int totalSystems = (widget.sequence.length / notesPerSystem).ceil();

    while (_horizontalControllers.length > totalSystems) {
      final orphanedController = _horizontalControllers.removeLast();
      orphanedController.dispose();
    }

    if (widget.currentPlayingIndex != -1 &&
        widget.currentPlayingIndex != oldWidget.currentPlayingIndex) {
      _scrollToActiveNote();
    }
  }

  void _scrollToActiveNote() {
    int notesPerSystem = widget.notesPerMeasure * widget.measuresPerLine;
    int sysIndex = widget.currentPlayingIndex ~/ notesPerSystem;
    int noteIndexInSys = widget.currentPlayingIndex % notesPerSystem;

    // Confine scrolling strictly to the internal tab container 
    // to prevent pushing the playback controls off screen.
    if (_verticalController.hasClients) {
      double vertOffset = sysIndex * 115.0; 
      _verticalController.animateTo(
        vertOffset,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
      );
    }

    if (sysIndex < _horizontalControllers.length &&
        _horizontalControllers[sysIndex].hasClients) {
      double horizOffset = max(0.0, (noteIndexInSys - 2) * 25.0);
      // FIX: Replaced animateTo with instant jumpTo to prevent layout tearing on 0.0ms chords
      _horizontalControllers[sysIndex].jumpTo(horizOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    int notesPerSystem = widget.notesPerMeasure * widget.measuresPerLine;
    int totalSystems = (widget.sequence.length / notesPerSystem).ceil();

    while (_horizontalControllers.length < totalSystems) {
      _horizontalControllers.add(ScrollController());
    }

    List<String> stringLabels = ["e", "B", "G", "D", "A", "E"];
    List<Widget> systemWidgets = [];

    for (int sysStart = 0; sysStart < widget.sequence.length; sysStart += notesPerSystem) {
      int sysEnd = min(sysStart + notesPerSystem, widget.sequence.length);
      int currentSysIndex = sysStart ~/ notesPerSystem;

      List<Widget> rowChildren = [];

      for (int offset = 0; offset < sysEnd - sysStart; offset++) {
        int noteIndex = sysStart + offset;
        var note = widget.sequence[noteIndex];
        int targetStr = note[0];
        int fret = note[1];

        bool isPlaying = (noteIndex == widget.currentPlayingIndex);
        bool isSelected = (widget.selectionStart != -1 &&
            widget.selectionEnd != -1 &&
            noteIndex >= widget.selectionStart &&
            noteIndex <= widget.selectionEnd);

        bool isMeasureEnd = (noteIndex + 1) % widget.notesPerMeasure == 0;
        int colWidth = (targetStr != -1 && fret >= 10) ? 4 : 3;

        rowChildren.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => widget.onBeatTapped(noteIndex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? Colors.amber.shade400
                        : (isSelected
                            ? Colors.blue.shade700.withOpacity(0.6)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Column(
                    children: List.generate(6, (strIdx) {
                      int strNum = strIdx + 1;
                      String text = "-" * colWidth;
                      if (targetStr == strNum) text = "-$fret-";

                      return Text(
                        text,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPlaying
                              ? Colors.black
                              : (isSelected
                                  ? Colors.cyanAccent
                                  : Colors.greenAccent),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              if (isMeasureEnd)
                Column(
                  children: List.generate(6, (_) => const Text("|",
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white54))),
                ),
            ],
          ),
        );
      }

      rowChildren.add(
        Column(
          children: List.generate(6, (_) => const Text("|",
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white54))),
        ),
      );

      rowChildren.add(const SizedBox(width: 48.0));

      systemWidgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: stringLabels
                    .map((lbl) => Text("$lbl|",
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)))
                    .toList(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _horizontalControllers[currentSysIndex],
                  scrollDirection: Axis.horizontal,
                  child: Row(children: rowChildren),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: SingleChildScrollView(
        controller: _verticalController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: systemWidgets,
        ),
      ),
    );
  }
}