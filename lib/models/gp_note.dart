/// Types of guitar slides supported in Guitar Pro tabs.
enum SlideType {
  none,
  intoFromBelow,
  intoFromAbove,
  outDownwards,
  outUpwards,
  legato,
  shift,
}

/// Types of harmonics.
enum HarmonicType {
  none,
  natural,
  artificial,
  pinch,
}

/// A single point on a bend envelope curve.
class BendPoint {
  final double position;
  final double offset;

  const BendPoint({
    required this.position,
    required this.offset,
  });

  @override
  String toString() => 'BendPoint(pos: $position, offset: $offset)';
}

/// Pitch bend metadata for guitar string bends and release curves.
class GpBend {
  final double maximumPitchOffset;
  final List<BendPoint> envelope;

  const GpBend({
    required this.maximumPitchOffset,
    required this.envelope,
  });

  /// Returns true if the bend envelope rises and then returns back down.
  bool get hasRelease {
    if (envelope.length < 2) return false;
    double maxVal = 0.0;
    for (final p in envelope) {
      if (p.offset > maxVal) maxVal = p.offset;
    }
    double finalVal = envelope.last.offset;
    return maxVal > 0.25 && finalVal < maxVal - 0.25;
  }

  @override
  String toString() => 'GpBend(max: $maximumPitchOffset, points: ${envelope.length})';
}

/// Vibrato modulation parameters for sustained notes.
class GpVibrato {
  final double amplitude;
  final double frequency;

  const GpVibrato({
    this.amplitude = 1.0,
    this.frequency = 5.0,
  });

  @override
  String toString() => 'GpVibrato(amp: $amplitude, freq: $frequency)';
}

/// A parsed Guitar Pro note with complete expressive technique metadata.
class GpNote {
  final int stringNum;
  final int fretNum;
  final int pitch;
  final double duration;
  final bool isTie;
  final bool isLetRing;
  final bool isMuted;
  final bool isPalmMute;
  final bool isLegato;
  final bool isGhost;
  final bool isTap;
  final HarmonicType harmonicType;
  final SlideType slideType;
  final GpBend? bend;
  final GpVibrato? vibrato;

  const GpNote({
    required this.stringNum,
    required this.fretNum,
    this.pitch = -1,
    this.duration = 0.25,
    this.isTie = false,
    this.isLetRing = false,
    this.isMuted = false,
    this.isPalmMute = false,
    this.isLegato = false,
    this.isGhost = false,
    this.isTap = false,
    this.harmonicType = HarmonicType.none,
    this.slideType = SlideType.none,
    this.bend,
    this.vibrato,
  });

  factory GpNote.rest({double duration = 0.25}) => GpNote(
        stringNum: -1,
        fretNum: -1,
        pitch: -1,
        duration: duration,
      );

  bool get isRest => stringNum == -1 || fretNum == -1;

  int operator [](int index) {
    if (index == 0) return stringNum;
    if (index == 1) return fretNum;
    throw RangeError.index(index, this, 'GpNote only indexes 0 (stringNum) and 1 (fretNum)');
  }

  List<int> toRaw() => [stringNum, fretNum];

  @override
  String toString() {
    if (isRest) return 'GpNote.rest(dur: $duration)';
    return 'GpNote(s: $stringNum, f: $fretNum, p: $pitch, dur: $duration'
        '${isTie ? ', tie' : ''}'
        '${isGhost ? ', ghost' : ''}'
        '${isTap ? ', tap' : ''}'
        '${harmonicType != HarmonicType.none ? ', harmonic' : ''}'
        '${isPalmMute ? ', PM' : ''}'
        '${isMuted ? ', mute' : ''}'
        '${bend != null ? ', bend' : ''}'
        '${vibrato != null ? ', vib' : ''})';
  }
}