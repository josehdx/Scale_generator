import 'dart:math';
import 'package:flutter/material.dart';
import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/master_bar_event.dart';

class BendPainter extends CustomPainter {
  final GpBeat beat;
  final Color color;

  BendPainter(this.beat, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // Height calculation (approx. 7 lines: 6 strings + 1 top annotation area)
    final double lineHeight = size.height / 7;

    for (final note in beat.notes) {
      if (note.isRest || note.bend == null) continue;
      final bend = note.bend!;
      final double startY = (note.stringNum) * lineHeight + (lineHeight / 2);
      final double startX = size.width / 2;
      final double apexY = lineHeight / 2;

      final path = Path();
      path.moveTo(startX, startY);

      if (bend.hasRelease) {
        path.quadraticBezierTo(startX + 10, apexY, startX + 20, startY);
        _drawArrowHead(canvas, paint, startX + 20, startY, false);
        _drawBendText(canvas, textPainter, bend.maximumPitchOffset, startX + 10, apexY - 14);
      } else {
        path.quadraticBezierTo(startX + 10, startY, startX + 15, apexY);
        _drawArrowHead(canvas, paint, startX + 15, apexY, true);
        _drawBendText(canvas, textPainter, bend.maximumPitchOffset, startX + 15, apexY - 14);
      }

      canvas.drawPath(path, paint);
    }
  }

  void _drawBendText(Canvas canvas, TextPainter textPainter, double offsetSemitones, double x, double y) {
    String text = "";
    if (offsetSemitones == 1.0) text = "1/2";
    else if (offsetSemitones == 2.0) text = "full";
    else if (offsetSemitones == 3.0) text = "1 1/2";
    else if (offsetSemitones == 4.0) text = "2";
    else if (offsetSemitones == 0.5) text = "1/4";
    else if (offsetSemitones > 0) text = (offsetSemitones / 2).toStringAsFixed(1);
    else return;

    textPainter.text = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - (textPainter.width / 2), y));
  }

  void _drawArrowHead(Canvas canvas, Paint paint, double x, double y, bool pointUp) {
    final path = Path();
    if (pointUp) {
      path.moveTo(x - 3, y + 4);
      path.lineTo(x, y);
      path.lineTo(x + 3, y + 4);
    } else {
      path.moveTo(x - 3, y - 4);
      path.lineTo(x, y);
      path.lineTo(x + 3, y - 4);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class InteractiveTabDisplay extends StatefulWidget {
  final List<GpBeat> sequence;
  final int notesPerMeasure;
  final int measuresPerLine;
  final int currentPlayingIndex;
  final ValueNotifier<int>? playingIndexNotifier;
  final int selectionStart;
  final int selectionEnd;
  final String tuningStr;
  final Function(int index) onBeatTapped;
  final List<int>? measureEndIndices;
  final List<MasterBarEvent>? masterBars;

  const InteractiveTabDisplay({
    super.key,
    required this.sequence,
    required this.notesPerMeasure,
    required this.measuresPerLine,
    required this.currentPlayingIndex,
    this.playingIndexNotifier,
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
  int _lastScrolledIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.playingIndexNotifier?.addListener(_onPlayheadChanged);
  }

  @override
  void dispose() {
    widget.playingIndexNotifier?.removeListener(_onPlayheadChanged);
    _verticalController.dispose();
    for (var controller in _horizontalControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onPlayheadChanged() {
    if (widget.playingIndexNotifier != null) {
      final newIndex = widget.playingIndexNotifier!.value;
      if (newIndex != _lastScrolledIndex && newIndex >= 0) {
        _lastScrolledIndex = newIndex;
        _scrollToActiveNote(newIndex);
      }
    }
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
    
    if (widget.playingIndexNotifier == null && widget.currentPlayingIndex != oldWidget.currentPlayingIndex) {
      _scrollToActiveNote(widget.currentPlayingIndex);
    }
  }

  void _scrollToActiveNote(int noteIndex) {
    if (noteIndex < 0) return;
    
    final systems = _calculateSystems();
    int sysIndex = -1;
    int noteIndexInSys = 0;

    for (int i = 0; i < systems.length; i++) {
      if (noteIndex >= systems[i].start && noteIndex < systems[i].end) {
        sysIndex = i;
        noteIndexInSys = noteIndex - systems[i].start;
        break;
      }
    }

    if (sysIndex == -1) return;

    if (_verticalController.hasClients) {
      final position = _verticalController.position;
      if (position.hasViewportDimension) {
        double vertOffset = sysIndex * 135.0;
        double currentVOffset = position.pixels;
        double vViewport = position.viewportDimension;
        
        if (vertOffset < currentVOffset || vertOffset + 135.0 > currentVOffset + vViewport) {
          _verticalController.animateTo(
            vertOffset,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
          );
        }
      }
    }

    if (sysIndex < _horizontalControllers.length && _horizontalControllers[sysIndex].hasClients) {
      final controller = _horizontalControllers[sysIndex];
      final position = controller.position;
      if (position.hasViewportDimension && position.maxScrollExtent > 0) {
        final int systemNotesCount = max(1, systems[sysIndex].end - systems[sysIndex].start);
        
        final double noteProgressRatio = systemNotesCount > 1
            ? (noteIndexInSys / (systemNotesCount - 1)).clamp(0.0, 1.0)
            : 0.0;

        final double totalContentWidth = position.maxScrollExtent + position.viewportDimension;
        final double targetOffset = (totalContentWidth * noteProgressRatio) - (position.viewportDimension / 2.0);
        final double safeOffset = targetOffset.clamp(0.0, position.maxScrollExtent);

        if ((safeOffset - position.pixels).abs() > 4.0) {
          controller.jumpTo(safeOffset);
        }
      }
    }
  }

  Widget _buildBeatContainer(bool isPlaying, bool isSelected, String topText, List<String> renderedStrings, int beatIndex, GpBeat beat) {
    return GestureDetector(
      onTap: () => widget.onBeatTapped(beatIndex),
      child: Container(
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: isPlaying
              ? Colors.amber.shade400
              : (isSelected
                  ? Colors.blue.shade700.withOpacity(0.6)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(2),
        ),
        child: CustomPaint(
          foregroundPainter: BendPainter(beat, isPlaying ? Colors.black : Colors.amberAccent),
          child: Column(
            children: [
              Text(
                topText,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isPlaying ? Colors.black : Colors.orangeAccent,
                ),
              ),
              ...List.generate(6, (strIdx) {
                final String textVal = renderedStrings[strIdx];
                final bool hasNote = textVal.contains(RegExp(r'[0-9x<>()/\\=]'));
                return Text(
                  textVal,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isPlaying
                        ? (hasNote ? Colors.black : Colors.black38)
                        : (isSelected
                            ? Colors.cyanAccent
                            : Colors.greenAccent),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
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
        int maxColWidth = 3;
        List<String> renderedStrings = List.filled(6, "");
        String topAnnotation = "";

        if (beat.strumDirection == StrumDirection.down) {
          topAnnotation += "v";
        } else if (beat.strumDirection == StrumDirection.up) {
          topAnnotation += "^";
        }

        for (int strIdx = 0; strIdx < 6; strIdx++) {
          final int strNum = strIdx + 1;
          final noteOnString = beat.noteOnString(strNum);

          if (noteOnString != null && !noteOnString.isRest) {
            String val = noteOnString.fretNum.toString();

            if (noteOnString.isMuted) {
              val = "x";
            } else if (noteOnString.harmonicType != HarmonicType.none) {
              val = "<$val>";
            } else if (noteOnString.isGhost || noteOnString.isTie) {
              val = "($val)";
            }

            if (noteOnString.slideType != SlideType.none) {
              bool slideUp = noteOnString.slideType == SlideType.intoFromBelow ||
                  noteOnString.slideType == SlideType.outUpwards ||
                  noteOnString.slideType == SlideType.shift ||
                  noteOnString.slideType == SlideType.legato;

              if (beatIndex + 1 < widget.sequence.length) {
                final nextBeat = widget.sequence[beatIndex + 1];
                final nextNote = nextBeat.noteOnString(strNum);
                if (nextNote != null && !nextNote.isRest) {
                  slideUp = nextNote.fretNum > noteOnString.fretNum;
                }
              }

              final String sChar = slideUp ? "/" : "\\";
              if (!topAnnotation.contains(sChar)) topAnnotation += sChar;
            }

            if (noteOnString.isTap && !topAnnotation.contains("t")) {
              topAnnotation += "t";
            }

            if (noteOnString.bend != null) {
              final String bSymbol = noteOnString.bend!.hasRelease ? "br" : "b";
              if (!topAnnotation.contains(bSymbol)) topAnnotation += bSymbol;
            }

            if (noteOnString.vibrato != null && !topAnnotation.contains("~")) {
              topAnnotation += "~";
            }

            if (noteOnString.isLegato && !topAnnotation.contains("h")) {
              topAnnotation += "h";
            }

            if (noteOnString.isPalmMute && !topAnnotation.contains("PM")) {
              topAnnotation += "PM";
            }

            if (noteOnString.isLetRing && !topAnnotation.contains("LR")) {
              topAnnotation += "LR";
            }

            String text = "-$val-";
            renderedStrings[strIdx] = text;
            if (text.length > maxColWidth) {
              maxColWidth = text.length;
            }
          }
        }

        String topText = "";
        if (topAnnotation.isNotEmpty) {
          topText = " $topAnnotation";
        }

        if (topText.length > maxColWidth) {
          maxColWidth = topText.length;
        }

        for (int strIdx = 0; strIdx < 6; strIdx++) {
          if (renderedStrings[strIdx].isEmpty) {
            renderedStrings[strIdx] = "-" * maxColWidth;
          } else {
            renderedStrings[strIdx] = renderedStrings[strIdx].padRight(maxColWidth, '-');
          }
        }

        if (topText.isEmpty) {
          topText = " " * maxColWidth;
        } else {
          topText = topText.padRight(maxColWidth, ' ');
        }

        rowChildren.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.playingIndexNotifier != null)
                ValueListenableBuilder<int>(
                  valueListenable: widget.playingIndexNotifier!,
                  builder: (context, pIdx, child) {
                    final bool isPlaying = (beatIndex == pIdx);
                    return _buildBeatContainer(isPlaying, isSelected, topText, renderedStrings, beatIndex, beat);
                  },
                )
              else
                _buildBeatContainer(beatIndex == widget.currentPlayingIndex, isSelected, topText, renderedStrings, beatIndex, beat),

              if (isMeasureEnd)
                Column(
                  children: [
                    const Text(
                      " ",
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    ...List.generate(
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
                  ],
                ),
            ],
          ),
        );
      }

      rowChildren.add(
        Column(
          children: [
            const Text(
              " ",
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            ...List.generate(
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
          ],
        ),
      );

      rowChildren.add(const SizedBox(width: 48.0));

      systemWidgets.add(
        SizedBox(
          height: 135.0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const Text(
                      "   ",
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    ...stringLabels.map(
                      (lbl) => Text(
                        "$lbl|",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                  ],
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

    return Scrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      thickness: 6.0,
      radius: const Radius.circular(4),
      interactive: true,
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