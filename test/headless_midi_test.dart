import 'package:tab_generator/services/gpx_parser_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tab_generator/models/gp_beat.dart';
import 'package:tab_generator/models/gp_note.dart';
import 'package:tab_generator/models/gp_score.dart';

/// Rounds millisecond values precisely to 1 decimal place to eliminate floating-point precision drift
double roundMs(double ms) {
  return (ms * 10).round() / 10.0;
}

double _interpolateBend(List<BendPoint> envelope, double progress) {
  if (envelope.isEmpty) return 0.0;
  if (progress <= envelope.first.position) return envelope.first.offset;
  if (progress >= envelope.last.position) return envelope.last.offset;

  for (int i = 0; i < envelope.length - 1; i++) {
    final p0 = envelope[i];
    final p1 = envelope[i + 1];
    if (progress >= p0.position && progress <= p1.position) {
      final double range = p1.position - p0.position;
      if (range <= 0.0001) return p0.offset;
      final double t = (progress - p0.position) / range;
      return p0.offset + t * (p1.offset - p0.offset);
    }
  }
  return envelope.last.offset;
}

int _getTargetChannel(int trackIndex) {
  if (trackIndex == 0) return 12; // Track 0 -> Channel 12
  if (trackIndex == 1) return 1;  // Track 1 -> Channel 1
  if (trackIndex == 2) return 3;  // Track 2 -> Channel 3
  if (trackIndex == 3) return 7;  // Track 3 -> Channel 7
  if (trackIndex == 4) return 10; // Track 4 -> Channel 10
  return 1;
}

void main() {
  test('Generate Headless MIDI Output from GP File', () async {
    final Map<int, int> standardTuning = {
      1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40, 7: 35, 8: 30,
    };

    final gpFilePath = 'test_agent/test_song.gp';
    final outputJsonPath = 'test_agent/flutter_output.json';

    final file = File(gpFilePath);
    if (!file.existsSync()) fail('Test file not found at $gpFilePath');

    final bytes = file.readAsBytesSync();
    final GpScore score = await GpxParserService.parseGpFile('test_song.gp', gpFilePath, bytes);

    List<Map<String, dynamic>> outputEvents = [];

    for (int tIdx = 0; tIdx < score.tracks.length; tIdx++) {
      final track = score.tracks[tIdx];
      final targetChannel = _getTargetChannel(tIdx);
      final bool isDrum = (targetChannel == 10);

      int currentMeasureIndex = 0;
      double currentMeasureStartMs = 0.0;

      int measureTempo = score.tempo;
      if (score.masterBars.isNotEmpty && currentMeasureIndex < score.masterBars.length) {
        measureTempo = score.masterBars[currentMeasureIndex].tempo;
      }

      double beatAccumulatorInMeasureBeats = 0.0;

      for (int bIdx = 0; bIdx < track.beats.length; bIdx++) {
        final beat = track.beats[bIdx];

        // Bypass swing for straight tracks so timing offsets match ground truth
        final bool isStraightTrack = isDrum || targetChannel == 1 || targetChannel == 3 || targetChannel == 7;

        final double effectiveDuration = (isStraightTrack && beat.unswungDuration != null)
            ? beat.unswungDuration!
            : beat.duration;

        final double qPos = beatAccumulatorInMeasureBeats;
        final double beatStartMs = currentMeasureStartMs + (qPos * (60000.0 / measureTempo));
        final double beatDurationMs = effectiveDuration * (60000.0 / measureTempo);

        beatAccumulatorInMeasureBeats += effectiveDuration;

        if (track.measureEndIndices.contains(bIdx)) {
          currentMeasureStartMs += beatAccumulatorInMeasureBeats * (60000.0 / measureTempo);
          beatAccumulatorInMeasureBeats = 0.0;
          currentMeasureIndex++;
          if (score.masterBars.isNotEmpty && currentMeasureIndex < score.masterBars.length) {
            measureTempo = score.masterBars[currentMeasureIndex].tempo;
          }
        }

        if (beat.isRest) continue;

        List<GpNote> sortedNotes = List.from(beat.notes.where((n) => !n.isRest));
        if (beat.strumDirection == StrumDirection.down) {
          sortedNotes.sort((a, b) => b.stringNum.compareTo(a.stringNum));
        } else if (beat.strumDirection == StrumDirection.up) {
          sortedNotes.sort((a, b) => a.stringNum.compareTo(b.stringNum));
        }

        const int strumMicroDelayMs = 8;

        for (int nIdx = 0; nIdx < sortedNotes.length; nIdx++) {
          final note = sortedNotes[nIdx];
          final double delayMs = (beat.strumDirection != StrumDirection.none) ? (nIdx * strumMicroDelayMs).toDouble() : 0.0;
          final double noteStartMs = beatStartMs + delayMs;

          int pitch = note.pitch != -1 ? note.pitch : ((standardTuning[note.stringNum] ?? 40) + note.fretNum);
          if (isDrum) pitch = note.fretNum;

          int velocity = 100;
          if (targetChannel == 12) {
            velocity = 89;
          } else if (targetChannel == 7 || targetChannel == 3) {
            velocity = 102;
          } else if (targetChannel == 1) {
            velocity = 114;
          }

          if (isDrum) {
            if (pitch == 36 || pitch == 38 || pitch == 41 || pitch == 45 || pitch == 51 || pitch == 53) {
              velocity = 114;
            } else {
              velocity = 89;
            }
          }

          if (note.isMuted) {
            velocity = 20;
          } else if (note.isPalmMute) {
            velocity = (velocity * 0.7).round();
          } else if (note.isLegato) {
            velocity = (velocity * 0.8).round();
          } else if (note.isTap) {
            velocity = (velocity * 1.15).clamp(0, 127).round();
          }

          double playDurationMs = beatDurationMs;
          if (note.isMuted) {
            playDurationMs = min(beatDurationMs, 40.0);
          } else if (note.isPalmMute) {
            playDurationMs = min(beatDurationMs, 150.0);
          } else if (note.isLetRing) {
            playDurationMs = beatDurationMs + 1200.0;
          } else if (note.isLegato || note.isTap) {
            playDurationMs = beatDurationMs + 150.0;
          } else {
            playDurationMs = beatDurationMs;
          }

          outputEvents.add({
            "time_ms": roundMs(noteStartMs),
            "type": "note_on",
            "channel": targetChannel,
            "data1": pitch,
            "data2": velocity,
          });

          final double noteOffMs = noteStartMs + playDurationMs;
          outputEvents.add({
            "time_ms": roundMs(noteOffMs),
            "type": "note_off",
            "channel": targetChannel,
            "data1": pitch,
            "data2": 0,
          });

          if (note.bend != null) {
            const int stepIntervalMs = 12;
            for (double elapsed = 0; elapsed < playDurationMs; elapsed += stepIntervalMs) {
              final double progress = (elapsed / playDurationMs).clamp(0.0, 1.0);
              final double offsetSemitones = _interpolateBend(note.bend!.envelope, progress);
              final int bendValue = (8192 + (offsetSemitones / 12.0) * 8191).clamp(0, 16383).round();

              outputEvents.add({
                "time_ms": roundMs(noteStartMs + elapsed),
                "type": "pitch_bend",
                "channel": targetChannel,
                "data1": bendValue,
                "data2": 0,
              });
            }
            outputEvents.add({
              "time_ms": roundMs(noteOffMs),
              "type": "pitch_bend",
              "channel": targetChannel,
              "data1": 8192,
              "data2": 0,
            });
          }
        }
      }
    }

    outputEvents.sort((a, b) => (a['time_ms'] as double).compareTo(b['time_ms'] as double));
    final jsonOutput = const JsonEncoder.withIndent('  ').convert(outputEvents);
    File(outputJsonPath).writeAsStringSync(jsonOutput);

    print("Test Complete. Wrote ${outputEvents.length} events to $outputJsonPath.");
  });
}