import 'dart:math';
import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/lick_preset.dart';
import '../scale_engine.dart';

/// Pre-calculated absolute MIDI event model.
class ScheduledMidiEvent implements Comparable<ScheduledMidiEvent> {
  final double timeMs;
  final String type; // 'note_on', 'note_off', 'pitch_bend'
  final int channel;
  final int data1;
  final int data2;
  final int trackIndex;
  final int beatIndex;
  final bool isMainTrack;
  final GpBend? bend;
  final GpVibrato? vibrato;
  final SlideType slideType;
  final double? durationMs;

  const ScheduledMidiEvent({
    required this.timeMs,
    required this.type,
    required this.channel,
    required this.data1,
    required this.data2,
    required this.trackIndex,
    required this.beatIndex,
    required this.isMainTrack,
    this.bend,
    this.vibrato,
    this.slideType = SlideType.none,
    this.durationMs,
  });

  @override
  int compareTo(ScheduledMidiEvent other) {
    final cmp = timeMs.compareTo(other.timeMs);
    if (cmp != 0) return cmp;
    if (type == 'note_off' && other.type == 'note_on') return -1;
    if (type == 'note_on' && other.type == 'note_off') return 1;
    return trackIndex.compareTo(other.trackIndex);
  }
}

/// Pure-Dart utility for calculating note sequences, rhythms, accents, and absolute timeline matrices.
class TabSequenceBuilder {
  final ScaleEngine engine;

  TabSequenceBuilder({required this.engine});

  static double roundMs(double ms) {
    return (ms * 10).round() / 10.0;
  }

  /// Synthesizes an absolute, sorted timeline matrix across multiple tracks.
  static List<ScheduledMidiEvent> buildAbsoluteTimeline({
    required List<GpBeat> beats,
    required List<int> measureEnds,
    required int initialTempo,
    required List<dynamic> masterBars,
    required int trackIndex,
    required int channel,
    required bool isMainTrack,
    double speedMultiplier = 1.0,
  }) {
    final List<ScheduledMidiEvent> timeline = [];
    if (beats.isEmpty) return timeline;

    int currentMeasureIndex = 0;
    double currentMeasureStartMs = 0.0;
    int measureTempo = initialTempo;

    if (masterBars.isNotEmpty && currentMeasureIndex < masterBars.length) {
      measureTempo = masterBars[currentMeasureIndex].tempo;
    }

    double beatAccumulatorInMeasureMs = 0.0;

    for (int i = 0; i < beats.length; i++) {
      final beat = beats[i];
      final double effectiveTempo = measureTempo * speedMultiplier;
      final double beatDurationMs = beat.duration * (60000.0 / effectiveTempo);
      final double beatStartMs = roundMs(currentMeasureStartMs + beatAccumulatorInMeasureMs);

      if (!beat.isRest) {
        for (final note in beat.notes) {
          if (note.isRest) continue;
          
          int pitch = note.pitch != -1 ? note.pitch : 60;
          int velocity = isMainTrack ? 110 : 80;
          double durationMs = beatDurationMs;

          if (note.isGhost) {
            velocity = (velocity * 0.5).round();
          }

          if (note.harmonicType == HarmonicType.natural) {
            pitch += 12; // Octave up
          } else if (note.harmonicType == HarmonicType.artificial || note.harmonicType == HarmonicType.pinch) {
            pitch += 24; // Two octaves up
          }

          if (note.isMuted) {
            velocity = 20;
            durationMs = min(beatDurationMs, 30.0);
          } else if (note.isPalmMute) {
            velocity = (velocity * 0.6).round();
            durationMs = beatDurationMs * 0.5;
          } else if (!note.isTie && !note.isLegato) {
            durationMs = max(1.0, durationMs - 1.0);
          }

          if (note.isLetRing) {
            durationMs = beatDurationMs * 1.5; 
          }

          final double noteOnMs = roundMs(beatStartMs);
          final double noteOffMs = roundMs(beatStartMs + durationMs);

          timeline.add(ScheduledMidiEvent(
            timeMs: noteOnMs,
            type: 'note_on',
            channel: channel,
            data1: pitch,
            data2: velocity,
            trackIndex: trackIndex,
            beatIndex: i,
            isMainTrack: isMainTrack,
            bend: note.bend,
            vibrato: note.vibrato,
            slideType: note.slideType,
            durationMs: durationMs,
          ));

          timeline.add(ScheduledMidiEvent(
            timeMs: noteOffMs,
            type: 'note_off',
            channel: channel,
            data1: pitch,
            data2: 0,
            trackIndex: trackIndex,
            beatIndex: i,
            isMainTrack: isMainTrack,
          ));
        }
      }

      beatAccumulatorInMeasureMs += beatDurationMs;

      if (measureEnds.contains(i)) {
        currentMeasureStartMs += beatAccumulatorInMeasureMs;
        beatAccumulatorInMeasureMs = 0.0;
        currentMeasureIndex++;
        if (masterBars.isNotEmpty && currentMeasureIndex < masterBars.length) {
          measureTempo = masterBars[currentMeasureIndex].tempo;
        }
      }
    }

    timeline.sort();
    return timeline;
  }

  bool isAutoAccent(String accentStr) => accentStr.toLowerCase().contains("auto");

  List<int> parseAccentPattern(String accentStr) {
    if (accentStr.isEmpty) return [127];
    List<String> parts = accentStr.split(',');
    List<int> accents = [];
    for (String p in parts) {
      if (p.trim() == "1") accents.add(127);
      else if (p.trim() == "0") accents.add(80);
      else {
        int? v = int.tryParse(p.trim());
        accents.add(v != null ? v.clamp(0, 127) : 80);
      }
    }
    if (accents.isEmpty) accents = [127];
    return accents;
  }

  List<String> parsePatternString(String patternName, {String? customRhythmOverride}) {
    if (patternName == "Custom Pattern" && customRhythmOverride != null && customRhythmOverride.isNotEmpty) {
      return customRhythmOverride.split(',').map((s) => s.trim() == "8" ? "8th" : "16th").toList();
    }
    switch (patternName) {
      case "Straight 16ths": return ["16th"];
      case "Straight 8ths": return ["8th"];
      case "Gallop (8-16-16)": return ["8th", "16th", "16th"];
      case "Reverse Gallop (16-16-8)": return ["16th", "16th", "8th"];
      case "Syncopated (16-8-16)": return ["16th", "8th", "16th"];
      default: return ["16th"];
    }
  }

  List<List<int>> parseManualTab(String input) {
    List<List<int>> sequence = [];
    List<String> parts = input.split(',');
    for (String p in parts) {
      p = p.trim();
      if (p.isEmpty) continue;
      if (p.toLowerCase() == 'r') {
        sequence.add([-1, -1]);
        continue;
      }
      List<String> noteTokens = (p.contains('+') || p.contains('/')) ? p.split(RegExp(r'[+/]')) : [p];
      for (String token in noteTokens) {
        List<String> sub = token.trim().split(':');
        if (sub.length == 2) {
          int? s = int.tryParse(sub[0]);
          int? f = int.tryParse(sub[1]);
          if (s != null && f != null && s >= 1 && s <= 8 && f >= 0 && f <= 24) {
            sequence.add([s, f]);
          }
        }
      }
    }
    return sequence;
  }

  List<GpBeat> sequenceToBeats(List<List<int>> sequence, {double defaultDuration = 0.25}) {
    return sequence.map((note) {
      if (note[0] == -1 || note[1] == -1) {
        return GpBeat.rest(duration: defaultDuration);
      }
      return GpBeat.single(
        GpNote(stringNum: note[0], fretNum: note[1], duration: defaultDuration),
        duration: defaultDuration,
      );
    }).toList();
  }

  List<List<int>> buildSequenceForPreset(
    LickPreset preset, {
    int selectionStart = -1,
    int selectionEnd = -1,
  }) {
    if (preset.system == "Manual Entry") {
      List<List<int>> base = parseManualTab(preset.manualTabString);
      List<List<int>> seq = engine.applyIntervalBreaks(base, preset.breakInterval, preset.breakLength);
      if (preset.endRests > 0) {
        if (selectionStart != -1 && selectionEnd != -1) {
          int insertIdx = max(selectionStart, selectionEnd) + 1;
          insertIdx = insertIdx.clamp(0, seq.length);
          seq.insertAll(insertIdx, List.generate(preset.endRests, (_) => [-1, -1]));
        } else {
          for (int i = 0; i < preset.endRests; i++) seq.add([-1, -1]);
        }
      }
      return seq;
    }

    engine.tunings[preset.tuning] ??= engine.openStrings;
    int stStr = 6;
    int enStr = 1;

    if (preset.system != "Single String Horizontal" && preset.fragment.contains('-') && !preset.fragment.contains('Strings')) {
      var parts = preset.fragment.split('-');
      stStr = (int.tryParse(parts[0]) ?? 6).clamp(1, 8);
      enStr = (int.tryParse(parts[1]) ?? 1).clamp(1, 8);
    }

    List<int> targetStrings = [];
    if (preset.system != "Single String Horizontal") {
      int minStr = min(stStr, enStr);
      int maxStr = max(stStr, enStr);
      targetStrings = [for (int i = minStr; i <= maxStr; i++) i];
    }

    Map<int, List<int>> boxDict;
    if (preset.system == "Single String Horizontal") {
      boxDict = engine.getScaleNotesSingleString(preset.key, preset.scale, preset.startFret, int.tryParse(preset.fragment) ?? 1);
    } else if (preset.system == "3-Note-Per-String (3NPS)") {
      boxDict = engine.getScaleNotes3NPS(preset.key, preset.scale, preset.startFret, targetStrings.isEmpty ? [1,2,3,4,5,6] : targetStrings);
    } else if (preset.system == "Custom Notes-Per-String") {
      List<int> npsProfile = (preset.customNps).split(',').map((e) => int.tryParse(e.trim()) ?? 3).toList();
      boxDict = engine.getScaleNotesCustomNPS(preset.key, preset.scale, preset.startFret, targetStrings.isEmpty ? [1,2,3,4,5,6] : targetStrings, npsProfile);
    } else {
      boxDict = engine.getScaleNotesBox(preset.key, preset.scale, preset.startFret, targetStrings.isEmpty ? [1,2,3,4,5,6] : targetStrings);
    }

    List<List<int>> currentSequence = [];
    if (preset.system == "Single String Horizontal") {
      int target = int.tryParse(preset.fragment) ?? 1;
      currentSequence = engine.flattenBoxDict(boxDict, target, target);
      if (preset.direction == "Descend -> Ascend" || preset.direction == "One-Way (Descend)") {
        currentSequence = currentSequence.reversed.toList();
      }
    } else {
      if (preset.pathway == "Custom Motif Builder") {
        List<String> tokens = (preset.motifString).split(',').where((s) => s.isNotEmpty).toList();
        currentSequence = engine.buildCustomMotif(boxDict, tokens.join(','), stStr, enStr);
      } else {
        List<List<int>> baseNotes = engine.flattenBoxDict(boxDict, stStr, enStr);
        if (preset.pathway == "Custom Sequence (Indices)") {
          String sequenceStr = preset.motifString.isNotEmpty ? preset.motifString : preset.fragment;
          currentSequence = engine.buildCustomSequence(baseNotes, sequenceStr);
        } else {
          List<List<int>> patternNotes;
          if (preset.pathway == "3-Step Triplet") patternNotes = engine.apply3StepSequence(baseNotes);
          else if (preset.pathway == "4-Step 16th") patternNotes = engine.apply4StepSequence(baseNotes);
          else if (preset.pathway == "Note Skipping") patternNotes = engine.applyNoteSkipping(baseNotes);
          else patternNotes = baseNotes;

          if (preset.direction.startsWith("One-Way")) currentSequence = patternNotes;
          else currentSequence = [...patternNotes, ...patternNotes.reversed.skip(1).toList()];
        }
      }
    }

    if (currentSequence.isNotEmpty) {
      currentSequence = engine.applyIntervalBreaks(currentSequence, preset.breakInterval, preset.breakLength);
      if (preset.endRests > 0) {
        if (selectionStart != -1 && selectionEnd != -1) {
          int insertIdx = max(selectionStart, selectionEnd) + 1;
          insertIdx = insertIdx.clamp(0, currentSequence.length);
          currentSequence.insertAll(insertIdx, List.generate(preset.endRests, (_) => [-1, -1]));
        } else {
          for (int i = 0; i < preset.endRests; i++) currentSequence.add([-1, -1]);
        }
      }
    }
    return currentSequence;
  }

  int calculateNotesPerMeasure(String timeSig, String rhythm, {String? customRhythm}) {
    if (timeSig != "Auto") {
      final List<String> parts = timeSig.split('/');
      if (parts.length == 2) {
        final int? num = int.tryParse(parts[0]);
        if (num != null && num > 0) return num * 4;
      }
    }
    List<String> parsed = parsePatternString(rhythm, customRhythmOverride: customRhythm);
    if (parsed.isEmpty) return 16;
    if (parsed.length == 3 && parsed[0] == "8th") return 12;
    return 16;
  }
}