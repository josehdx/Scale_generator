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
  /// Normalised position inside the note, 0.0 (attack) .. 1.0 (end).
  final double position;

  /// Pitch offset in semitones (1.0 = one semitone, 2.0 = full-step bend).
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

  bool get hasRelease {
    if (envelope.length < 2) return false;
    double maxVal = 0.0;
    for (final p in envelope) {
      if (p.offset > maxVal) maxVal = p.offset;
    }
    final double finalVal = envelope.last.offset;
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
///
/// * [stringNum] is the DISPLAY string: 1 = highest-pitched string of the
///   track (so a 4-string bass uses 1..4, a 7-string guitar uses 1..7).
/// * [pitch] is the SOUNDING MIDI pitch. Tuning, capo and harmonics are
///   already resolved by the parser; playback must not transpose it again.
/// * [isTie] is true only for the tie DESTINATION (the note that continues a
///   previous one and must not be re-attacked). The tie origin is a normal note.
class GpNote {
  final int stringNum;
  final int fretNum;
  final int pitch;
  final double duration;
  final bool isTie;
  final bool isTieOrigin;
  final bool isLetRing;
  final bool isMuted;
  final bool isPalmMute;

  /// True for the destination of a hammer-on / pull-off (not picked).
  final bool isLegato;

  /// True for the note that starts a hammer-on / pull-off.
  final bool isHopoOrigin;
  final bool isGhost;
  final bool isTap;
  final bool isPercussion;
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
    this.isTieOrigin = false,
    this.isLetRing = false,
    this.isMuted = false,
    this.isPalmMute = false,
    this.isLegato = false,
    this.isHopoOrigin = false,
    this.isGhost = false,
    this.isTap = false,
    this.isPercussion = false,
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

  GpNote copyWith({double? duration}) => GpNote(
        stringNum: stringNum,
        fretNum: fretNum,
        pitch: pitch,
        duration: duration ?? this.duration,
        isTie: isTie,
        isTieOrigin: isTieOrigin,
        isLetRing: isLetRing,
        isMuted: isMuted,
        isPalmMute: isPalmMute,
        isLegato: isLegato,
        isHopoOrigin: isHopoOrigin,
        isGhost: isGhost,
        isTap: isTap,
        isPercussion: isPercussion,
        harmonicType: harmonicType,
        slideType: slideType,
        bend: bend,
        vibrato: vibrato,
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
        '${isLegato ? ', hopo' : ''}'
        '${slideType != SlideType.none ? ', ${slideType.name}' : ''}'
        '${harmonicType != HarmonicType.none ? ', harmonic' : ''}'
        '${isPalmMute ? ', PM' : ''}'
        '${isMuted ? ', mute' : ''}'
        '${bend != null ? ', bend' : ''}'
        '${vibrato != null ? ', vib' : ''})';
  }
}