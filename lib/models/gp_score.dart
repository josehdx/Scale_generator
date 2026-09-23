import 'gp_track.dart';
import 'master_bar_event.dart';

/// Parsed result of a Guitar Pro (.gp) file.
///
/// Holds song-level metadata, the master timeline automation events,
/// and the ordered list of [GpTrack]s produced by [GpxParserService.parseGpFile].
class GpScore {
  /// Song title from the GPIF `<Title>` element.
  final String title;

  /// Artist name from the GPIF `<Artist>` element.
  final String artist;

  /// Initial or global tempo in BPM.
  final int tempo;

  /// Notes per measure derived from the initial `<MasterBar><Time>` element
  /// (numerator × 4). Defaults to 16.
  final int notesPerMeasure;

  /// Timeline of all measures in the score, including tempo and time signature automations.
  final List<MasterBarEvent> masterBars;

  /// Ordered list of parsed tracks. Never empty after a successful parse;
  /// contains at least one synthetic "All Tracks" entry as a fallback.
  final List<GpTrack> tracks;

  const GpScore({
    required this.title,
    required this.artist,
    required this.tempo,
    required this.notesPerMeasure,
    this.masterBars = const [],
    required this.tracks,
  });
}
