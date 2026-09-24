import 'gp_note.dart';

enum StrumDirection { none, down, up }

class GpBeat {
  final List<GpNote> notes;
  final double duration;
  final double? unswungDuration;
  final StrumDirection strumDirection;
  final int voiceIndex;

  const GpBeat({
    required this.notes,
    required this.duration,
    this.unswungDuration,
    this.strumDirection = StrumDirection.none,
    this.voiceIndex = 0,
  });

  factory GpBeat.rest({double duration = 0.25, int voiceIndex = 0}) => GpBeat(
        notes: [GpNote.rest(duration: duration)],
        duration: duration,
        unswungDuration: duration,
        voiceIndex: voiceIndex,
      );

  factory GpBeat.single(GpNote note, {double? duration, int voiceIndex = 0}) => GpBeat(
        notes: [note],
        duration: duration ?? note.duration,
        unswungDuration: duration ?? note.duration,
        voiceIndex: voiceIndex,
      );

  bool get isRest => notes.isEmpty || notes.every((n) => n.isRest);
  bool get isChord => notes.where((n) => !n.isRest).length > 1;

  GpNote? noteOnString(int stringNum) {
    for (final n in notes) {
      if (n.stringNum == stringNum) return n;
    }
    return null;
  }
}