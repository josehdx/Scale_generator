import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/gpx_parser_service.dart';
import '../lib/utils/tab_sequence_builder.dart';
void main() {
  test('Headless MIDI generation test', () async {
    // 1. Set the exact path to your new .gp / .gpx file
    const String gpFilePath = 'benchmark.gp';
    final file = File(gpFilePath);
    
    expect(file.existsSync(), true, reason: 'File $gpFilePath does not exist');
    
    // 2. Parse the GP Score
    final score = await GpxParserService.parseGpFile(file.path, file.path, null);
    expect(score.tracks.isNotEmpty, true, reason: 'No tracks found in GP file');

    // 3. ISOLATE TARGET TRACK (Crucial)
    // Select the index corresponding to the lead/melodic track matching your .mid file (usually 0)
    const int targetTrackIndex = 0; 
    final targetTrack = score.tracks[targetTrackIndex];

    // 4. Build absolute timeline ONLY for the selected track on Channel 1
    // (Channel 1 matches the 1-indexed output of convert_midi.py)
    final timeline = TabSequenceBuilder.buildAbsoluteTimeline(
      beats: targetTrack.beats,
      measureEnds: targetTrack.measureEndIndices,
      initialTempo: score.tempo,
      masterBars: score.masterBars,
      trackIndex: targetTrackIndex,
      channel: 1, // Set to 1 to match convert_midi.py
      isMainTrack: true,
      speedMultiplier: 1.0,
    );

    // 5. Transform timeline events into the evaluation JSON format
    final List<Map<String, dynamic>> outputEvents = [];

    for (final ev in timeline) {
      if (ev.type == 'note_on' || ev.type == 'note_off') {
        outputEvents.add({
          "time_ms": ev.timeMs,
          "type": ev.type,
          "channel": ev.channel,
          "data1": ev.data1, // MIDI Pitch
          "data2": ev.data2  // Velocity
        });
      }
    }

    // 6. Ensure test_agent/ directory exists and write flutter_output.json
    final outputDir = Directory('test_agent');
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final outputFile = File('test_agent/flutter_output.json');
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(outputEvents),
    );

    print('Successfully exported ${outputEvents.length} events for track "${targetTrack.name}" to ${outputFile.path}');
  });
}