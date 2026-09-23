import 'gp_beat.dart';
import 'gp_note.dart';

/// Data model and enumerations shared by the GP Viewer feature.

/// Three-state loop mode for GP playback.
enum LoopMode {
  /// Play once to the end and stop.
  off,

  /// Loop the entire active track continuously.
  all,

  /// Loop strictly between [selectionStart] and [selectionEnd].
  selection,
}

/// A parsed Guitar Pro track: metadata + ordered list of [GpBeat]s.
///
/// * [id]                – Track identifier from the GPIF XML (or a synthetic index string).
/// * [name]              – Human-readable track name (e.g. "Lead Guitar").
/// * [beats]             – Ordered sequence of [GpBeat] instances (chords, notes, rests).
/// * [measureEndIndices] – Beat indices that terminate each measure.
class GpTrack {
  final String id;
  final String name;
  final List<GpBeat> beats;
  final List<int> measureEndIndices;

  const GpTrack({
    required this.id,
    required this.name,
    required this.beats,
    this.measureEndIndices = const [],
  });

  /// Flattened list of all notes across beats.
  List<GpNote> get allNotes => beats.expand((b) => b.notes).toList();

  /// Rhythmic durations corresponding to each beat.
  List<double> get rhythms => beats.map((b) => b.duration).toList();
}
