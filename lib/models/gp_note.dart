/// Types of guitar slides supported in Guitar Pro tabs.
enum SlideType {
  none,
  intoFromBelow,
  intoFromAbove,
  outDownwards,
  outUpwards,
  legato,
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
  /// Normalized position in the note's duration (0.0 = start, 1.0 = end).
  final double position;
  /// Pitch offset in semitones (e.g. 1.0 = half step, 2.0 = whole step).
  final double offset;

  const BendPoint({
    required this.position,
    required this.offset,
  });

  @override
  String toString() => 'BendPoint(pos: $position, offset:$offset)';
}

/// Pitch bend metadata for guitar string bends and release curves.
class GpBend {
  /// Maximum pitch offset in semitones across the envelope.
  final double maximumPitchOffset;
  /// Envelope curve points describing bend progression over time.
  final List<BendPoint> envelope;

  const GpBend({
    required this.maximumPitchOffset,
    required this.envelope,
  });

  @override
  String toString() => 'GpBend(max: $maximumPitchOffset, points:${envelope.length})';
}

/// Vibrato modulation parameters for sustained notes.
class GpVibrato {
  /// Modulation depth / amplitude (0.0 to 1.0+).
  final double amplitude;
  /// Modulation frequency in Hertz (typically 4.0 - 6.0 Hz).
  final double frequency;

  const GpVibrato({
    this.amplitude = 1.0,
    this.frequency = 5.0,
  });

  @override
  String toString() => 'GpVibrato(amp: $amplitude, freq:$frequency)';
}

/// A parsed Guitar Pro note with complete expressive technique metadata.
class GpNote {
  /// 1-indexed guitar string (1 = high E, 6 = low E; up to 8 strings).
  /// A value of -1 denotes a musical rest.
  final int stringNum;
  /// Fret number on the string (-1 for rest).
  final int fretNum;
  /// Computed MIDI pitch (e.g. 64 for E4; -1 for rest).
  final int pitch;
  /// Rhythmic duration multiplier where 1.0 = quarter note, 0.5 = 8th note, etc.
  final double duration;
  
  /// Whether this note is tied to the preceding note (do not retrigger Note-On).
  final bool isTie;
  /// Whether this note rings freely beyond its strict rhythmic duration.
  final bool isLetRing;
  /// Whether this is a dead / muted note (displayed as 'x').
  final bool isMuted;
  /// Whether this note is palm-muted (P.M.).
  final bool isPalmMute;
  /// Whether this note is played legato (hammer-on / pull-off).
  final bool isLegato;
  /// Whether this is a ghost note (faintly played, displayed as '(fret)').
  final bool isGhost;
  
  /// Type of harmonic applied to the note.
  final HarmonicType harmonicType;
  /// Slide technique applied to this note.
  final SlideType slideType;
  /// Pitch bend articulation, if present.
  final GpBend? bend;
  /// Vibrato articulation, if present.
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
    this.harmonicType = HarmonicType.none,
    this.slideType = SlideType.none,
    this.bend,
    this.vibrato,
  });

  /// Convenience factory for a musical rest.
  factory GpNote.rest({double duration = 0.25}) => GpNote(
        stringNum: -1,
        fretNum: -1,
        pitch: -1,
        duration: duration,
      );

  /// True if this note represents silence / rest.
  bool get isRest => stringNum == -1 || fretNum == -1;

  /// Index operator allowing backward-compatible access as `[stringNum, fretNum]`.
  int operator [](int index) {
    if (index == 0) return stringNum;
    if (index == 1) return fretNum;
    throw RangeError.index(index, this, 'GpNote only indexes 0 (stringNum) and 1 (fretNum)');
  }

  /// Converts this note to a raw `[stringNum, fretNum]` pair.
  List<int> toRaw() => [stringNum, fretNum];

  @override
  String toString() {
    if (isRest) return 'GpNote.rest(dur: $duration)';
    return 'GpNote(s: $stringNum, f:$fretNum, p: $pitch, dur:$duration'
        '${isTie ? ', tie' : ''}'
        '${isGhost ? ', ghost' : ''}'
        '${harmonicType != HarmonicType.none ? ', harmonic' : ''}'
        '${isPalmMute ? ', PM' : ''}'
        '${isMuted ? ', mute' : ''}'
        '${bend != null ? ', bend' : ''}'
        '${vibrato != null ? ', vib' : ''})';
  }
}