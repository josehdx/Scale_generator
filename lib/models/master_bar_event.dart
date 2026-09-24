class MasterBarEvent {
  final int barIndex;
  final int tempo;
  final int numerator;
  final int denominator;
  final int startTick;
  final double startMs;
  final double durationMs;
  final String tripletFeel;

  const MasterBarEvent({
    required this.barIndex,
    required this.tempo,
    required this.numerator,
    required this.denominator,
    required this.startTick,
    required this.startMs,
    required this.durationMs,
    this.tripletFeel = '',
  });

  int get sixteenthCount => (numerator * (16 / denominator)).round();
}