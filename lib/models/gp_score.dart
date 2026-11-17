import 'gp_track.dart';
import 'master_bar_event.dart';

/// Parsed result of a Guitar Pro (.gp) file.
class GpScore {
  /// The original file name of the parsed file.
  final String fileName;

  /// The permanent local file path to the copied .gp file
  final String filePath;

  /// Song title from the GPIF `<Title>` element.
  final String title;

  /// Artist name from the GPIF `<Artist>` element.
  final String artist;

  /// Initial tempo in BPM.
  final int tempo;

  /// Sixteenth notes in the first measure.
  final int notesPerMeasure;

  /// One entry per written master bar (tempo map, time signatures, repeats).
  final List<MasterBarEvent> masterBars;

  /// Master-bar indices in PLAYBACK order, with repeats and alternate endings
  /// unrolled. Equal to 0..n-1 when the song has no repeats.
  final List<int> playOrder;

  /// Ordered list of parsed tracks.
  final List<GpTrack> tracks;

  const GpScore({
    required this.fileName,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.tempo,
    required this.notesPerMeasure,
    this.masterBars = const [],
    this.playOrder = const [],
    required this.tracks,
  });

  /// Cleanly formats the title and artist for the UI
  String get songTitleFormatted {
    if (title.isEmpty) return artist;
    if (artist.isEmpty) return title;
    return '$title - $artist';
  }
}