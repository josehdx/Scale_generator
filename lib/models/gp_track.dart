import 'gp_beat.dart';
import 'gp_note.dart';

/// Data model and enumerations shared by the GP Viewer feature.

/// Three-state loop mode for GP playback.
enum LoopMode {
  /// Play once to the end and stop.
  off,

  /// Loop the entire active track continuously.
  all,

  /// Loop strictly between selectionStart and selectionEnd.
  selection,
}

/// A parsed Guitar Pro track: metadata + ordered list of [GpBeat]s.
///
/// * [id]                – Track identifier (index string).
/// * [name]              – Human-readable track name (e.g. "Lead Guitar").
/// * [beats]             – Beats in WRITTEN order (repeats are not unrolled;
///                         see `GpScore.playOrder`). Every master bar owns at
///                         least one beat, so [measureEndIndices] has exactly
///                         one entry per master bar.
/// * [measureEndIndices] – Index of the last beat of each master bar.
/// * [tuning]            – Open-string MIDI pitches, LOWEST string first
///                         (empty for percussion / unknown).
/// * [capo]              – Capo fret (already included in note pitches).
/// * [isPercussion]      – Drum track: route to MIDI channel 9.
class GpTrack {
  final String id;
  final String name;
  final List<GpBeat> beats;
  final List<int> measureEndIndices;
  final List<int> tuning;
  final int capo;
  final bool isPercussion;

  const GpTrack({
    required this.id,
    required this.name,
    required this.beats,
    this.measureEndIndices = const [],
    this.tuning = const [],
    this.capo = 0,
    this.isPercussion = false,
  });

  /// Number of tab lines to draw (6 when unknown).
  int get stringCount {
    if (isPercussion) return 6;
    return tuning.isEmpty ? 6 : tuning.length;
  }

  /// Index of the first beat of master bar [bar].
  int barStartIndex(int bar) {
    if (bar <= 0) return 0;
    if (bar - 1 >= measureEndIndices.length) return beats.length;
    return measureEndIndices[bar - 1] + 1;
  }

  /// Master bar that contains [beatIndex] (binary search).
  int barOfBeat(int beatIndex) {
    int lo = 0;
    int hi = measureEndIndices.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (measureEndIndices[mid] >= beatIndex) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Flattened list of all notes across beats.
  List<GpNote> get allNotes => beats.expand((b) => b.notes).toList();

  /// Rhythmic durations corresponding to each beat.
  List<double> get rhythms => beats.map((b) => b.duration).toList();
}