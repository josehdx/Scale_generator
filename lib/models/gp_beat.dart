import 'gp_note.dart';

/// Represents a single rhythmic beat or chord column in a Guitar Pro track.
///
/// A [GpBeat] groups one or more [GpNote] instances that sound simultaneously
/// at this beat position (e.g. a single note, a multi-string chord, or a musical rest).
class GpBeat {
  /// All notes sounding simultaneously in this beat / chord.
  final List<GpNote> notes;

  /// Rhythmic duration multiplier (1.0 = quarter note, 0.5 = 8th note, 0.25 = 16th note).
  final double duration;

  const GpBeat({
    required this.notes,
    required this.duration,
  });

  /// Creates a musical rest beat with the specified [duration].
  factory GpBeat.rest({double duration = 0.25}) => GpBeat(
        notes: [GpNote.rest(duration: duration)],
        duration: duration,
      );

  /// Creates a single-note beat.
  factory GpBeat.single(GpNote note, {double? duration}) => GpBeat(
        notes: [note],
        duration: duration ?? note.duration,
      );

  /// True if this beat represents silence (empty notes list or only rest notes).
  bool get isRest => notes.isEmpty || notes.every((n) => n.isRest);

  /// True if this beat contains multiple distinct non-rest notes (a chord).
  bool get isChord => notes.where((n) => !n.isRest).length > 1;

  /// Returns the note assigned to [stringNum] (1-indexed: 1 = high E), or null if none.
  GpNote? noteOnString(int stringNum) {
    for (final n in notes) {
      if (n.stringNum == stringNum) return n;
    }
    return null;
  }

  @override
  String toString() {
    if (isRest) return 'GpBeat.rest(dur: $duration)';
    if (isChord) return 'GpBeat.chord(${notes.length} notes, dur: $duration)';
    return 'GpBeat.single(${notes.first}, dur: $duration)';
  }
}

