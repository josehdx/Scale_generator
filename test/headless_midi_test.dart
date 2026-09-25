import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/models/gp_score.dart';
import 'package:tab_generator/services/gpx_parser_service.dart';
import 'package:tab_generator/utils/tab_sequence_builder.dart';

void main() {
  test('Headless MIDI generation test', () async {
    final String gpFilePath = 'test_agent/test_song.gp';
    final List<int> bytes = await File(gpFilePath).readAsBytes();

    // Fix: Add null-assertion (!) to unwrap GpScore? returned by parseGpFile
    final GpScore score = (await GpxParserService.parseGpFile(
      'test_song.gp',
      gpFilePath,
      bytes,
    ))!;

    expect(score.tracks, isNotEmpty);

    final track = score.tracks.first;
    final timeline = TabSequenceBuilder.buildAbsoluteTimeline(
      beats: track.beats,
      measureEnds: track.measureEndIndices,
      initialTempo: score.tempo,
      masterBars: score.masterBars,
      trackIndex: 0,
      channel: 1,
      isMainTrack: true,
    );

    expect(timeline, isNotEmpty);
  });
}