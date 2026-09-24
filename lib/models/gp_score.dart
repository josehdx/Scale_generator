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
  
  /// Initial or global tempo in BPM.
  final int tempo;
  
  /// Notes per measure derived from the initial `<MasterBar><Time>` element.
  final int notesPerMeasure;
  
  /// Timeline of all measures in the score, including tempo and time signature automations.
  final List<MasterBarEvent> masterBars;
  
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
    required this.tracks,
  });

  /// Cleanly formats the title and artist for the UI
  String get songTitleFormatted => title.isNotEmpty ? '$title -$artist' : artist;
}