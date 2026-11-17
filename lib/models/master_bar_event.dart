/// A tempo change that happens inside a bar.
class TempoChange {
  /// Position inside the bar, 0.0 .. 1.0.
  final double ratio;

  /// Tempo in quarter-note BPM.
  final double bpm;

  const TempoChange({required this.ratio, required this.bpm});

  @override
  String toString() => 'TempoChange(@${(ratio * 100).toStringAsFixed(0)}% -> $bpm)';
}

class MasterBarEvent {
  final int barIndex;

  /// Tempo at the START of the bar (quarter-note BPM, rounded).
  final int tempo;
  final int numerator;
  final int denominator;
  final int startTick;

  /// Start of the bar in the WRITTEN (not unrolled) timeline at 100% speed.
  final double startMs;
  final double durationMs;
  final String tripletFeel;

  /// Tempo segments of this bar, sorted by ratio; always starts at ratio 0.
  /// Empty means "constant [tempo]".
  final List<TempoChange> tempoChanges;

  final bool isRepeatStart;
  final bool isRepeatEnd;

  /// Total number of times the repeated section is played (>= 2 when
  /// [isRepeatEnd]).
  final int repeatCount;

  /// 1-based pass numbers this bar belongs to (volta brackets). Empty = all.
  final List<int> alternateEndings;

  const MasterBarEvent({
    required this.barIndex,
    required this.tempo,
    required this.numerator,
    required this.denominator,
    required this.startTick,
    required this.startMs,
    required this.durationMs,
    this.tripletFeel = '',
    this.tempoChanges = const [],
    this.isRepeatStart = false,
    this.isRepeatEnd = false,
    this.repeatCount = 0,
    this.alternateEndings = const [],
  });

  int get sixteenthCount => (numerator * (16 / denominator)).round();

  /// Bar length in quarter notes.
  double get quarters => numerator * (4.0 / denominator);

  /// Tempo in force at the end of the bar (carried into the next bar).
  double get endTempo => tempoChanges.isEmpty ? tempo.toDouble() : tempoChanges.last.bpm;

  /// Converts an offset from the bar start (in quarter notes) to milliseconds
  /// at 100% speed, honouring tempo changes inside the bar. Offsets past the
  /// end of the bar continue at the last tempo.
  double quartersToMs(double q) {
    if (q <= 0) return 0.0;
    final List<TempoChange> segs =
        tempoChanges.isEmpty ? [TempoChange(ratio: 0, bpm: tempo.toDouble())] : tempoChanges;
    final double total = quarters;
    double ms = 0.0;
    for (int k = 0; k < segs.length; k++) {
      final double segStart = segs[k].ratio * total;
      final double segEnd = (k + 1 < segs.length) ? segs[k + 1].ratio * total : double.infinity;
      if (q <= segStart) break;
      final double overlapEnd = q < segEnd ? q : segEnd;
      final double bpm = segs[k].bpm <= 0 ? 120.0 : segs[k].bpm;
      ms += (overlapEnd - segStart) * (60000.0 / bpm);
    }
    return ms;
  }
}