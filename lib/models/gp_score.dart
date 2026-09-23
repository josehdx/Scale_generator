import 'gp_track.dart';

/// Parsed result of a Guitar Pro (.gp) file.
///
/// Holds song-level metadata and the ordered list of [GpTrack]s produced
/// by [GpxParserService.parseGpFile].
class GpScore {
  /// Song title from the GPIF `<Title>` element.
  final String title;

  /// Artist name from the GPIF `<Artist>` element.
  final String artist;

  /// Tempo in BPM extracted from the first `<Automation type="Tempo">`.
  final int tempo;

  /// Notes per measure derived from the first `<MasterBar><Time>` element
  /// (numerator × 4). Defaults to 16.
  final int notesPerMeasure;

  /// Ordered list of parsed tracks. Never empty after a successful parse;
  /// contains at least one synthetic "All Tracks" entry as a fallback.
  final List<GpTrack> tracks;

  const GpScore({
    required this.title,
    required this.artist,
    required this.tempo,
    required this.notesPerMeasure,
    required this.tracks,
  });
}

