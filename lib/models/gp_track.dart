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

/// A parsed Guitar Pro track: metadata + ordered list of [stringNum, fretNum] notes.
///
/// * [id]    – Track identifier from the GPIF XML (or a synthetic index string).
/// * [name]  – Human-readable track name (e.g. "Lead Guitar").
/// * [notes] – Ordered note sequence as `[[stringNum, fretNum], ...]`.
///             `stringNum` is 1-indexed (1 = high-e, 6 = low-E).
class GpTrack {
  final String id;
  final String name;
  final List<List<int>> notes;
  final List<double> rhythms;

  const GpTrack({
    required this.id,
    required this.name,
    required this.notes,
    required this.rhythms,
  });
}

