import 'dart:math';
import 'package:flutter/material.dart';

import '../models/gp_beat.dart';
import '../models/master_bar_event.dart';

class InteractiveTabDisplay extends StatefulWidget {
  final List<GpBeat> sequence;
  final int notesPerMeasure;
  final int measuresPerLine;
  final int currentPlayingIndex;
  final int selectionStart;
  final int selectionEnd;
  final String tuningStr;
  final Function(int index) onBeatTapped;

  /// Optional measure boundary note/beat indices for dynamic time signatures.
  final List<int>? measureEndIndices;

  /// Optional MasterBar automation events timeline.
  final List<MasterBarEvent>? masterBars;

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
    this.measureEndIndices,
    this.masterBars,
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

  List<({int start, int end})> _calculateSystems() {
    if (widget.sequence.isEmpty) return [];

    final ends = widget.measureEndIndices;
    if (ends != null && ends.isNotEmpty) {
      final List<({int start, int end})> systems = [];
      int currentMeasureInSystem = 0;
      int sysStart = 0;

      for (int m = 0; m < ends.length; m++) {
        int mEnd = ends[m];
        if (mEnd >= widget.sequence.length) {
          mEnd = widget.sequence.length - 1;
        }

        currentMeasureInSystem++;
        if (currentMeasureInSystem == widget.measuresPerLine || m == ends.length - 1) {
          int sysEnd = mEnd + 1;
          if (m == ends.length - 1 && sysEnd < widget.sequence.length) {
            sysEnd = widget.sequence.length;
          }
          systems.add((start: sysStart, end: sysEnd));
          sysStart = sysEnd;
          currentMeasureInSystem = 0;

          if (sysStart >= widget.sequence.length) break;
        }
      }

      if (sysStart < widget.sequence.length) {
        systems.add((start: sysStart, end: widget.sequence.length));
      }
      return systems;
    }

    // Default fixed-length measure division
    final int notesPerSystem = widget.notesPerMeasure * widget.measuresPerLine;
    final List<({int start, int end})> systems = [];

    for (int sysStart = 0; sysStart < widget.sequence.length; sysStart += notesPerSystem) {
      final int sysEnd = min(sysStart + notesPerSystem, widget.sequence.length);
      systems.add((start: sysStart, end: sysEnd));
    }

    return systems;
  }

  bool _isMeasureEnd(int noteIndex) {
    if (widget.measureEndIndices != null && widget.measureEndIndices!.isNotEmpty) {
      return widget.measureEndIndices!.contains(noteIndex);
    }
    return (noteIndex + 1) % widget.notesPerMeasure == 0;
  }

  @override
  void didUpdateWidget(covariant InteractiveTabDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    final systems = _calculateSystems();
    final int totalSystems = systems.length;

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
    final systems = _calculateSystems();
    int sysIndex = -1;
    int noteIndexInSys = 0;

    for (int i = 0; i < systems.length; i++) {
      if (widget.currentPlayingIndex >= systems[i].start &&
          widget.currentPlayingIndex < systems[i].end) {
        sysIndex = i;
        noteIndexInSys = widget.currentPlayingIndex - systems[i].start;
        break;
      }
    }

    if (sysIndex == -1) return;

    if (_verticalController.hasClients) {
      final position = _verticalController.position;
      if (position.hasViewportDimension) {
        double vertOffset = sysIndex * 115.0;
        double currentVOffset = position.pixels;
        double vViewport = position.viewportDimension;
        
        // Edge boundary tracking logic: only jump if the system leaves the viewing area
        if (vertOffset < currentVOffset || vertOffset + 115.0 > currentVOffset + vViewport) {
          _verticalController.animateTo(
            vertOffset,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
      }
    }

    if (sysIndex < _horizontalControllers.length &&
        _horizontalControllers[sysIndex].hasClients) {
          
      final position = _horizontalControllers[sysIndex].position;
      if (position.hasViewportDimension) {
        double currentOffset = position.pixels;
        double viewportWidth = position.viewportDimension;
        double targetNotePos = noteIndexInSys * 28.0; // Approx column width tracking
        
        // Horizontal Edge boundary tracking logic: only jump if playhead leaves the middle 80% screen space
        if (targetNotePos < currentOffset + 20.0 || targetNotePos > currentOffset + viewportWidth - 40.0) {
          double horizOffset = max(0.0, targetNotePos - (viewportWidth / 2));
          _horizontalControllers[sysIndex].animateTo(
            horizOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      } else {
        // Safe layout fallback if viewport dims aren't attached yet
        double horizOffset = max(0.0, (noteIndexInSys - 2) * 25.0);
        _horizontalControllers[sysIndex].jumpTo(horizOffset);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final systems = _calculateSystems();
    final int totalSystems = systems.length;

    while (_horizontalControllers.length < totalSystems) {
      _horizontalControllers.add(ScrollController());
    }

    final List<String> stringLabels = ["e", "B", "G", "D", "A", "E"];
    final List<Widget> systemWidgets = [];

    for (int sIdx = 0; sIdx < systems.length; sIdx++) {
      final sys = systems[sIdx];
      final List<Widget> rowChildren = [];

      for (int beatIndex = sys.start; beatIndex < sys.end; beatIndex++) {
        final beat = widget.sequence[beatIndex];
        final bool isPlaying = (beatIndex == widget.currentPlayingIndex);

        int effectiveEnd = (widget.selectionStart != -1 && widget.selectionEnd != -1)
            ? max(widget.selectionStart, widget.selectionEnd)
            : -1;
            
        if (effectiveEnd != -1 && beatIndex > effectiveEnd && beat.isRest) {
          bool allRests = true;
          for (int r = effectiveEnd + 1; r <= beatIndex; r++) {
            if (r < widget.sequence.length && !widget.sequence[r].isRest) {
              allRests = false;
              break;
            }
          }
          if (allRests) effectiveEnd = beatIndex;
        }

        final bool isSelected = (widget.selectionStart != -1 &&
            effectiveEnd != -1 &&
            beatIndex >= min(widget.selectionStart, widget.selectionEnd) &&
            beatIndex <= effectiveEnd);
            
        final bool isMeasureEnd = _isMeasureEnd(beatIndex);

        final bool hasDoubleDigitFret =
            beat.notes.any((n) => !n.isRest && n.fretNum >= 10);
        final int colWidth = hasDoubleDigitFret ? 4 : 3;

        rowChildren.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => widget.onBeatTapped(beatIndex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? Colors.amber.shade400
                        : (isSelected
                            ? Colors.blue.shade700.withValues(alpha: 0.6)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Column(
                    children: List.generate(6, (strIdx) {
                      final int strNum = strIdx + 1;
                      final noteOnString = beat.noteOnString(strNum);
                      String text;

                      if (noteOnString != null && !noteOnString.isRest) {
                        if (colWidth == 4) {
                          text = noteOnString.fretNum >= 10
                              ? "-${noteOnString.fretNum}-"
                              : "-${noteOnString.fretNum}--";
                        } else {
                          text = "-${noteOnString.fretNum}-";
                        }
                      } else {
                        text = "-" * colWidth;
                      }

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
                  children: List.generate(
                    6,
                    (_) => const Text(
                      "|",
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }

      rowChildren.add(
        Column(
          children: List.generate(
            6,
            (_) => const Text(
              "|",
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white54,
              ),
            ),
          ),
        ),
      );

      rowChildren.add(const SizedBox(width: 48.0));

      systemWidgets.add(
        SizedBox(
          height: 115.0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: stringLabels
                      .map(
                        (lbl) => Text(
                          "$lbl|",
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amberAccent,
                          ),
                        ),
                      )
                      .toList(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontalControllers[sIdx],
                    scrollDirection: Axis.horizontal,
                    child: Row(children: rowChildren),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Returning standard SingleChildScrollView (removed double-boxing borders so Studio & GP Viewer align perfectly)
    return SingleChildScrollView(
      controller: _verticalController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: systemWidgets,
      ),
    );
  }
}