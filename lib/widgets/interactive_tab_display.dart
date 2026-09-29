import 'dart:math';
import 'package:flutter/material.dart';
import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/master_bar_event.dart';

class BeatRenderData {
  final String topText;
  final List<String> strings;
  final List<bool> hasNotes;
  final bool isMeasureEnd;
  final GpBeat beat;

  BeatRenderData({
    required this.topText,
    required this.strings,
    required this.hasNotes,
    required this.isMeasureEnd,
    required this.beat,
  });
}

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

    const double topMargin = 36.0;
    const double lineHeight = 18.0;

    for (final note in beat.notes) {
      if (note.isRest || note.bend == null) continue;
      final bend = note.bend!;

      final double startY = topMargin + lineHeight + ((note.stringNum - 1) * lineHeight) + (lineHeight / 2);
      final double startX = size.width / 2;
      final double apexY = 16.0; 

      final path = Path();
      path.moveTo(startX, startY);

      if (bend.hasRelease) {
        path.quadraticBezierTo(startX + 10, apexY, startX + 20, startY);
        _drawArrowHead(canvas, paint, startX + 20, startY, false);
        _drawBendText(canvas, textPainter, bend.maximumPitchOffset, startX + 10, apexY - 14.0);
      } else {
        path.quadraticBezierTo(startX + 10, startY, startX + 15, apexY);
        _drawArrowHead(canvas, paint, startX + 15, apexY, true);
        _drawBendText(canvas, textPainter, bend.maximumPitchOffset, startX + 15, apexY - 14.0);
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
  bool shouldRepaint(covariant BendPainter oldDelegate) {
    return oldDelegate.beat != beat || oldDelegate.color != color;
  }
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
  static final RegExp _noteRegex = RegExp(r'[0-9x<>()/\\=]');
  
  final ScrollController _verticalController = ScrollController();
  late List<ScrollController> _horizontalControllers;
  late List<ValueNotifier<bool>> _beatNotifiers;
  
  List<({int start, int end})> _cachedSystems = [];
  List<BeatRenderData> _cachedRenderData = [];
  Set<int> _measureEndSet = {};
  int _effectiveSelectionEnd = -1;
  
  int _lastScrolledIndex = -1;
  int _lastActiveIndex = -1;

  // Telemetry variables
  DateTime? _lastScrollTime;

  @override
  void initState() {
    super.initState();
    _rebuildCache();
    
    if (widget.playingIndexNotifier != null) {
      _lastActiveIndex = widget.playingIndexNotifier!.value;
      if (_lastActiveIndex >= 0 && _lastActiveIndex < _beatNotifiers.length) {
        _beatNotifiers[_lastActiveIndex].value = true;
      }
      widget.playingIndexNotifier!.addListener(_onPlayheadChanged);
    }
  }

  @override
  void dispose() {
    widget.playingIndexNotifier?.removeListener(_onPlayheadChanged);
    _verticalController.dispose();
    for (var controller in _horizontalControllers) {
      controller.dispose();
    }
    for (var notifier in _beatNotifiers) {
      notifier.dispose();
    }
    super.dispose();
  }

  void _rebuildCache() {
    _measureEndSet = widget.measureEndIndices?.toSet() ?? {};
    _cachedSystems = _calculateSystems();
    _effectiveSelectionEnd = _calculateEffectiveSelectionEnd();
    
    _horizontalControllers = List.generate(_cachedSystems.length, (_) => ScrollController());
    _beatNotifiers = List.generate(widget.sequence.length, (_) => ValueNotifier<bool>(false));
    
    _cachedRenderData = List.generate(widget.sequence.length, (index) => _buildViewModelForBeat(index));
  }

  int _calculateEffectiveSelectionEnd() {
    if (widget.selectionStart == -1 || widget.selectionEnd == -1) return -1;
    
    int end = max(widget.selectionStart, widget.selectionEnd);
    for (int r = end + 1; r < widget.sequence.length; r++) {
      if (widget.sequence[r].isRest) {
        end = r;
      } else {
        break;
      }
    }
    return end;
  }

  BeatRenderData _buildViewModelForBeat(int beatIndex) {
    final beat = widget.sequence[beatIndex];
    final bool isMeasureEnd = _measureEndSet.contains(beatIndex) || (beatIndex + 1) % widget.notesPerMeasure == 0;

    int maxColWidth = 3;
    List<String> renderedStrings = List.filled(6, "");
    List<bool> hasNotes = List.filled(6, false);
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
        hasNotes[strIdx] = false;
      } else {
        hasNotes[strIdx] = _noteRegex.hasMatch(renderedStrings[strIdx]);
        renderedStrings[strIdx] = renderedStrings[strIdx].padRight(maxColWidth, '-');
      }
    }

    if (topText.isEmpty) {
      topText = " " * maxColWidth;
    } else {
      topText = topText.padRight(maxColWidth, ' ');
    }

    return BeatRenderData(
      topText: topText,
      strings: renderedStrings,
      hasNotes: hasNotes,
      isMeasureEnd: isMeasureEnd,
      beat: beat,
    );
  }

  void _onPlayheadChanged() {
    if (widget.playingIndexNotifier != null) {
      final newIndex = widget.playingIndexNotifier!.value;
      
      if (_lastActiveIndex >= 0 && _lastActiveIndex < _beatNotifiers.length) {
        _beatNotifiers[_lastActiveIndex].value = false;
      }
      if (newIndex >= 0 && newIndex < _beatNotifiers.length) {
        _beatNotifiers[newIndex].value = true;
      }

      if (newIndex != _lastScrolledIndex && newIndex >= 0) {
        _lastScrolledIndex = newIndex;
        _scrollToActiveNote(newIndex);
      }
      
      _lastActiveIndex = newIndex;
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

  @override
  void didUpdateWidget(covariant InteractiveTabDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.sequence != oldWidget.sequence || widget.measuresPerLine != oldWidget.measuresPerLine) {
      for (var controller in _horizontalControllers) {
        controller.dispose();
      }
      for (var notifier in _beatNotifiers) {
        notifier.dispose();
      }
      
      _rebuildCache();
      
      _lastActiveIndex = widget.playingIndexNotifier?.value ?? -1;
      if (_lastActiveIndex >= 0 && _lastActiveIndex < _beatNotifiers.length) {
        _beatNotifiers[_lastActiveIndex].value = true;
      }
    } else if (widget.selectionStart != oldWidget.selectionStart || widget.selectionEnd != oldWidget.selectionEnd) {
      setState(() {
        _effectiveSelectionEnd = _calculateEffectiveSelectionEnd();
      });
    }
    
    if (widget.playingIndexNotifier == null && widget.currentPlayingIndex != oldWidget.currentPlayingIndex) {
      _scrollToActiveNote(widget.currentPlayingIndex);
    }
  }

  void _scrollToActiveNote(int noteIndex) {
    if (noteIndex < 0) return;
    
    int sysIndex = -1;
    int noteIndexInSys = 0;
    
    for (int i = 0; i < _cachedSystems.length; i++) {
      if (noteIndex >= _cachedSystems[i].start && noteIndex < _cachedSystems[i].end) {
        sysIndex = i;
        noteIndexInSys = noteIndex - _cachedSystems[i].start;
        break;
      }
    }

    if (sysIndex == -1) return;

    if (_verticalController.hasClients) {
      final position = _verticalController.position;
      if (position.hasViewportDimension) {
        double vertOffset = sysIndex * 190.0;
        double currentVOffset = position.pixels;
        double vViewport = position.viewportDimension;
        
        if (vertOffset < currentVOffset || vertOffset + 190.0 > currentVOffset + vViewport) {
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
        final int systemNotesCount = max(1, _cachedSystems[sysIndex].end - _cachedSystems[sysIndex].start);
        
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

  Widget _buildBeatLayout(bool isPlaying, bool isSelected, BeatRenderData data, int beatIndex) {
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
          foregroundPainter: BendPainter(data.beat, isPlaying ? Colors.black : Colors.amberAccent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 36.0),
              Container(
                height: 18.0,
                alignment: Alignment.center,
                child: Text(
                  data.topText,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isPlaying ? Colors.black : Colors.orangeAccent,
                  ),
                ),
              ),
              ...List.generate(6, (strIdx) {
                final String textVal = data.strings[strIdx];
                final bool hasNote = data.hasNotes[strIdx];
                return Container(
                  height: 18.0,
                  alignment: Alignment.center,
                  child: Text(
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
    final List<String> stringLabels = ["e", "B", "G", "D", "A", "E"];

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification is ScrollUpdateNotification) {
          final now = DateTime.now();
          if (_lastScrollTime != null) {
            final deltaMs = now.difference(_lastScrollTime!).inMilliseconds;
            if (deltaMs > 16) {
              debugPrint('[SCROLL TELEMETRY] Dropped Frame: ${deltaMs}ms | Scroll Delta: ${notification.scrollDelta?.toStringAsFixed(1)}');
            }
          }
          _lastScrollTime = now;
        } else if (notification is ScrollEndNotification) {
          _lastScrollTime = null;
        }
        return false;
      },
      child: Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        thickness: 6.0,
        radius: const Radius.circular(4),
        interactive: true,
        child: ListView.builder(
          controller: _verticalController,
          physics: const BouncingScrollPhysics(),
          itemCount: _cachedSystems.length,
          itemBuilder: (context, sIdx) {
            final sys = _cachedSystems[sIdx];
            final int systemBeatCount = sys.end - sys.start;

            return SizedBox(
              height: 190.0,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 36.0),
                        Container(height: 18.0, alignment: Alignment.center, child: const Text(" ")),
                        ...stringLabels.map(
                          (lbl) => Container(
                            height: 18.0,
                            alignment: Alignment.center,
                            child: Text(
                              "$lbl|",
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _horizontalControllers[sIdx],
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: systemBeatCount + 2, 
                        itemBuilder: (context, horizontalIndex) {
                          if (horizontalIndex < systemBeatCount) {
                            final int beatIndex = sys.start + horizontalIndex;
                            final BeatRenderData data = _cachedRenderData[beatIndex];

                            final bool isSelected = (widget.selectionStart != -1 &&
                                _effectiveSelectionEnd != -1 &&
                                beatIndex >= min(widget.selectionStart, widget.selectionEnd) &&
                                beatIndex <= _effectiveSelectionEnd);

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.playingIndexNotifier != null)
                                  ValueListenableBuilder<bool>(
                                    valueListenable: _beatNotifiers[beatIndex],
                                    builder: (context, isPlaying, _) {
                                      return _buildBeatLayout(isPlaying, isSelected, data, beatIndex);
                                    }
                                  )
                                else
                                  _buildBeatLayout(beatIndex == widget.currentPlayingIndex, isSelected, data, beatIndex),
                                
                                if (data.isMeasureEnd)
                                  Column(
                                    children: [
                                      const SizedBox(height: 36.0),
                                      Container(height: 18.0, alignment: Alignment.center, child: const Text(" ")),
                                      ...List.generate(
                                        6,
                                        (_) => Container(
                                          height: 18.0,
                                          alignment: Alignment.center,
                                          child: const Text(
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
                              ],
                            );
                          } else if (horizontalIndex == systemBeatCount) {
                            return Column(
                              children: [
                                const SizedBox(height: 36.0),
                                Container(height: 18.0, alignment: Alignment.center, child: const Text(" ")),
                                ...List.generate(
                                  6,
                                  (_) => Container(
                                    height: 18.0,
                                    alignment: Alignment.center,
                                    child: const Text(
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
                            );
                          } else {
                            return const SizedBox(width: 48.0);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}