import 'dart:math';

import '../models/gp_note.dart';

/// One sample of a pitch curve: [tMs] after the note's attack, [semitones]
/// away from the note's pitch.
class PitchSample {
  final double tMs;
  final double semitones;
  const PitchSample(this.tMs, this.semitones);
}

/// Pure functions that turn bends, vibrato and slides into sampled pitch
/// curves. The timeline builder converts the samples into `pitch_bend` events,
/// so no async "bend loops" are needed during playback.
class PitchCurve {
  PitchCurve._();

  static const double stepMs = 30.0;

  /// The soundfont's bend range is configured to +/- [range] semitones.
  static int toBendValue(double semitones, {double range = 12.0}) {
    final double s = semitones.clamp(-range, range).toDouble();
    return (8192 + (s / range) * 8191).round().clamp(0, 16383);
  }

  static double interpolate(List<BendPoint> envelope, double progress) {
    if (envelope.isEmpty) return 0.0;
    if (progress <= envelope.first.position) return envelope.first.offset;
    if (progress >= envelope.last.position) return envelope.last.offset;
    for (int i = 0; i < envelope.length - 1; i++) {
      final BendPoint p0 = envelope[i];
      final BendPoint p1 = envelope[i + 1];
      if (progress >= p0.position && progress <= p1.position) {
        final double range = p1.position - p0.position;
        if (range <= 0.0001) return p1.offset;
        final double t = (progress - p0.position) / range;
        return p0.offset + t * (p1.offset - p0.offset);
      }
    }
    return envelope.last.offset;
  }

  static List<PitchSample> _sample(double durationMs, double Function(double tMs) f) {
    final List<PitchSample> out = [];
    for (double t = 0.0; t < durationMs; t += stepMs) {
      out.add(PitchSample(t, f(t)));
    }
    out.add(PitchSample(durationMs, 0.0)); // always return to neutral
    return out;
  }

  static List<PitchSample> bend(GpBend bend, double durationMs) {
    if (durationMs <= 0 || bend.envelope.isEmpty) return const [];
    return _sample(durationMs, (t) => interpolate(bend.envelope, t / durationMs));
  }

  static List<PitchSample> vibrato(GpVibrato v, double durationMs) {
    if (durationMs <= 0) return const [];
    final double start = durationMs * 0.2;
    return _sample(durationMs, (t) {
      if (t < start) return 0.0;
      return sin(2 * pi * v.frequency * (t - start) / 1000.0) * (v.amplitude * 0.4);
    });
  }

  /// Slides.
  ///
  /// * [firstSegmentMs]: length of the note's own beat (a legato slide can
  ///   sustain over several beats; the glide happens at the end of the first).
  /// * [targetSemitones]: distance to the destination note for shift / legato
  ///   slides (null when there is no destination note).
  static List<PitchSample> slide(
    SlideType type,
    double durationMs, {
    required double firstSegmentMs,
    double? targetSemitones,
  }) {
    if (durationMs <= 0) return const [];
    switch (type) {
      case SlideType.intoFromBelow:
      case SlideType.intoFromAbove:
        final double sign = type == SlideType.intoFromBelow ? -1.0 : 1.0;
        final double glide = min(durationMs * 0.3, 150.0);
        return _sample(durationMs, (t) => t >= glide ? 0.0 : sign * 3.0 * (1.0 - t / glide));
      case SlideType.outDownwards:
      case SlideType.outUpwards:
        final double sign = type == SlideType.outDownwards ? -1.0 : 1.0;
        final double from = durationMs * 0.6;
        final double span = durationMs - from;
        return _sample(durationMs, (t) => t <= from || span <= 0 ? 0.0 : sign * 5.0 * ((t - from) / span));
      case SlideType.shift:
      case SlideType.legato:
        final double? target = targetSemitones;
        if (target == null) return const [];
        final double goal = target.clamp(-12.0, 12.0).toDouble();
        final double gStart = firstSegmentMs * 0.5;
        final double gEnd = firstSegmentMs;
        return _sample(durationMs, (t) {
          if (t <= gStart) return 0.0;
          if (t >= gEnd) return goal;
          return goal * ((t - gStart) / (gEnd - gStart));
        });
      case SlideType.none:
        return const [];
    }
  }
}