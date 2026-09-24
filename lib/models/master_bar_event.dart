/// Represents musical parameters (tempo, time signature, timing anchors)
/// for a single measure (MasterBar) in a Guitar Pro score.
class MasterBarEvent {
  /// Zero-based index of this measure in the song timeline.
  final int barIndex;

  /// Tempo in BPM effective during this measure.
  final int tempo;

  /// Time signature numerator (e.g. 4 in 4/4, 6 in 6/8).
  final int numerator;

  /// Time signature denominator (e.g. 4 in 4/4, 8 in 6/8).
  final int denominator;

  /// Cumulative tick start position in standard MIDI ticks (960 ticks per quarter).
  final int startTick;

  /// Cumulative start time from the start of the score in milliseconds.
  final double startMs;

  /// Duration of this measure in milliseconds at the specified [tempo].
  final double durationMs;

  const MasterBarEvent({
    required this.barIndex,
    required this.tempo,
    required this.numerator,
    required this.denominator,
    required this.startTick,
    required this.startMs,
    required this.durationMs,
  });

  /// The length of this measure expressed in quarter note equivalents.
  /// E.g. 4/4 -> 4.0, 3/4 -> 3.0, 6/8 -> 3.0.
  double get quarterCount => numerator * (4.0 / denominator);

  /// Number of 16th note divisions in this measure (useful for grid visualization).
  int get sixteenthCount => (quarterCount * 4).round();

  /// Cumulative start time in milliseconds from the beginning of the score.
  double get cumulativeStartMs => startMs;

  @override
  String toString() =>
      'MasterBarEvent(bar: $barIndex, $numerator/$denominator @ $tempo BPM, start: ${startMs.toStringAsFixed(1)}ms)';
}

