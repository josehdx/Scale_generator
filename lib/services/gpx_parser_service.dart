import 'dart:math';
import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/lick_preset.dart';
import '../models/master_bar_event.dart';
import '../scale_engine.dart';

class TabNote {
  final int midiPitch;
  final double startTimeMs;
  final double durationMs;
  final int velocity;
  final bool isTie;
  final bool isLegato;

  TabNote({
    required this.midiPitch,
    required this.startTimeMs,
    required this.durationMs,
    required this.velocity,
    this.isTie = false,
    this.isLegato = false,
  });
}

class MidiEvent {
  final double timestampMs;
  final int pitch;
  final int velocity;
  final bool isNoteOn;

  MidiEvent({
    required this.timestampMs,
    required this.pitch,
    required this.velocity,
    required this.isNoteOn,
  });
}

class ScheduledMidiEvent implements Comparable<ScheduledMidiEvent> {
  final double timeMs;
  final String type; // 'note_on' or 'note_off'
  final int channel;
  final int data1;
  final int data2;
  final int trackIndex;
  final int beatIndex;
  final bool isMainTrack;

  ScheduledMidiEvent({
    required this.timeMs,
    required this.type,
    required this.channel,
    required this.data1,
    required this.data2,
    required this.trackIndex,
    required this.beatIndex,
    required this.isMainTrack,
  });

  @override
  int compareTo(ScheduledMidiEvent other) {
    int timeCompare = timeMs.compareTo(other.timeMs);
    if (timeCompare != 0) return timeCompare;

    bool aIsNoteOn = type == 'note_on';
    bool bIsNoteOn = other.type == 'note_on';
    if (aIsNoteOn == bIsNoteOn) return 0;
    return aIsNoteOn ? 1 : -1;
  }
}

class TabSequenceBuilder {
  final ScaleEngine engine;

  TabSequenceBuilder({ScaleEngine? engine}) : engine = engine ?? ScaleEngine();

  static double roundMs(double val) {
    return (val * 10).round() / 10.0;
  }

  List<MidiEvent> buildSequence(List<TabNote> notes) {
    List<MidiEvent> midiEvents = [];

    for (var note in notes) {
      if (note.isTie) continue;

      double durationMs = note.durationMs;

      if (!note.isLegato) {
        durationMs = max(1.0, durationMs - 16.0);
      }

      midiEvents.add(MidiEvent(
        timestampMs: note.startTimeMs,
        pitch: note.midiPitch,
        velocity: note.velocity,
        isNoteOn: true,
      ));

      midiEvents.add(MidiEvent(
        timestampMs: note.startTimeMs + durationMs,
        pitch: note.midiPitch,
        velocity: 0,
        isNoteOn: false,
      ));
    }

    midiEvents.sort((a, b) {
      int timeCompare = a.timestampMs.compareTo(b.timestampMs);
      if (timeCompare != 0) return timeCompare;

      if (a.isNoteOn == b.isNoteOn) return 0;
      return a.isNoteOn ? 1 : -1;
    });

    return midiEvents;
  }

  static List<ScheduledMidiEvent> buildAbsoluteTimeline({
    required List<GpBeat> beats,
    required List<int> measureEnds,
    required int initialTempo,
    required List<MasterBarEvent> masterBars,
    required int trackIndex,
    required int channel,
    required bool isMainTrack,
    required double speedMultiplier,
  }) {
    List<ScheduledMidiEvent> events = [];
    if (beats.isEmpty) return events;

    double currentMs = 0.0;
    int currentBarIndex = 0;
    int currentTempo = initialTempo;

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final beat = beats[bIdx];

      if (masterBars.isNotEmpty && currentBarIndex < masterBars.length) {
        currentTempo = masterBars[currentBarIndex].tempo;
      }

      final double effectiveTempo = currentTempo * speedMultiplier;
      final double beatDurationMs = beat.duration * (60000.0 / effectiveTempo);

      if (!beat.isRest) {
        for (final note in beat.notes) {
          if (note.isRest || note.isTie) continue;
          int pitch = note.pitch > 0 ? note.pitch : 60;

          int velocity = isMainTrack ? 110 : 80;
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

          events.add(ScheduledMidiEvent(
            timeMs: roundMs(currentMs),
            type: 'note_on',
            channel: channel,
            data1: pitch,
            data2: velocity,
            trackIndex: trackIndex,
            beatIndex: bIdx,
            isMainTrack: isMainTrack,
          ));

          events.add(ScheduledMidiEvent(
            timeMs: roundMs(currentMs + playDurationMs),
            type: 'note_off',
            channel: channel,
            data1: pitch,
            data2: 0,
            trackIndex: trackIndex,
            beatIndex: bIdx,
            isMainTrack: isMainTrack,
          ));
        }
      }

      currentMs += beatDurationMs;

      if (measureEnds.contains(bIdx)) {
        currentBarIndex++;
      }
    }

    events.sort((a, b) => a.compareTo(b));
    return events;
  }

  List<List<int>> buildSequenceForPreset(
    LickPreset preset, {
    int? selectionStart,
    int? selectionEnd,
  }) {
    if (preset.system == "Manual Entry") {
      List<List<int>> manualSeq = [];
      List<String> parts = preset.manualTabString
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      for (String p in parts) {
        if (p.toLowerCase() == 'r') {
          manualSeq.add([-1, -1]);
        } else if (p.contains(':')) {
          var sub = p.replaceAll(RegExp(r'\([^\)]*\)'), '').split(':');
          if (sub.length == 2) {
            int? s = int.tryParse(sub[0]);
            int? f = int.tryParse(sub[1]);
            if (s != null && f != null) manualSeq.add([s, f]);
          }
        }
      }
      return manualSeq;
    }

    engine.setTuning(preset.tuning);

    int startStr = 6;
    int endStr = 1;
    int singleStrTarget = 1;

    if (preset.system == "Single String Horizontal") {
      singleStrTarget = int.tryParse(preset.fragment) ?? 1;
    } else if (preset.fragment.contains('-')) {
      var parts = preset.fragment.split('-');
      startStr = int.tryParse(parts[0]) ?? 6;
      endStr = int.tryParse(parts[1]) ?? 1;
    }

    List<int> targetStrings = [];
    if (startStr >= endStr) {
      for (int s = startStr; s >= endStr; s--) targetStrings.add(s);
    } else {
      for (int s = startStr; s <= endStr; s++) targetStrings.add(s);
    }

    Map<int, List<int>> boxDict = {};

    if (preset.system == "Box Position / CAGED") {
      boxDict = engine.getScaleNotesBox(
          preset.key, preset.scale, preset.startFret, targetStrings);
    } else if (preset.system == "3-Note-Per-String (3NPS)") {
      boxDict = engine.getScaleNotes3NPS(
          preset.key, preset.scale, preset.startFret, targetStrings);
    } else if (preset.system == "Custom Notes-Per-String") {
      List<int> profile = preset.customNps
          .split(',')
          .map((e) => int.tryParse(e.trim()) ?? 3)
          .toList();
      boxDict = engine.getScaleNotesCustomNPS(
          preset.key, preset.scale, preset.startFret, targetStrings, profile);
    } else if (preset.system == "Single String Horizontal") {
      boxDict = engine.getScaleNotesSingleString(
          preset.key, preset.scale, preset.startFret, singleStrTarget);
    }

    List<List<int>> sequence = [];

    if (preset.pathway == "Straight Linear") {
      sequence = engine.flattenBoxDict(boxDict, startStr, endStr);
    } else if (preset.pathway == "3-Step Triplet") {
      sequence = engine.apply3StepSequence(
          engine.flattenBoxDict(boxDict, startStr, endStr));
    } else if (preset.pathway == "4-Step 16th") {
      sequence = engine.apply4StepSequence(
          engine.flattenBoxDict(boxDict, startStr, endStr));
    } else if (preset.pathway == "Note Skipping") {
      sequence = engine.applyNoteSkipping(
          engine.flattenBoxDict(boxDict, startStr, endStr));
    } else if (preset.pathway == "Custom Sequence (Indices)") {
      sequence = engine.buildCustomSequence(
          engine.flattenBoxDict(boxDict, startStr, endStr), preset.motifString);
    } else if (preset.pathway == "Custom Motif Builder") {
      if (preset.system == "Single String Horizontal") {
        sequence = engine.buildSingleStringMotif(
            boxDict, preset.motifString, singleStrTarget, preset.direction);
      } else {
        sequence = engine.buildCustomMotif(
            boxDict, preset.motifString, startStr, endStr);
      }
    }

    return engine.applyIntervalBreaks(
        sequence, preset.breakInterval, preset.breakLength);
  }

  List<String> parsePatternString(
    String pattern, {
    String? customRhythmOverride,
  }) {
    if (pattern == "Custom Pattern" &&
        customRhythmOverride != null &&
        customRhythmOverride.trim().isNotEmpty) {
      List<String> result = [];
      for (var token in customRhythmOverride.split(',')) {
        String clean = token.trim();
        if (clean == "16" || clean == "16th") {
          result.add("16th");
        } else if (clean == "8" || clean == "8th") {
          result.add("8th");
        } else if (clean == "4" || clean == "Quarter") {
          result.add("Quarter");
        } else if (clean == "32" || clean == "32nd") {
          result.add("32nd");
        } else {
          result.add("16th");
        }
      }
      return result.isEmpty ? ["16th"] : result;
    }

    switch (pattern) {
      case "Straight 8ths":
        return ["8th"];
      case "Gallop (8-16-16)":
        return ["8th", "16th", "16th"];
      case "Reverse Gallop (16-16-8)":
        return ["16th", "16th", "8th"];
      case "Syncopated (16-8-16)":
        return ["16th", "8th", "16th"];
      case "Straight 16ths":
      default:
        return ["16th"];
    }
  }

  List<int> parseAccentPattern(String accentStr) {
    if (accentStr.trim().isEmpty) return [89];
    List<int> velocities = [];
    for (var part in accentStr.split(',')) {
      String clean = part.trim();
      if (clean == "1") {
        velocities.add(127);
      } else {
        velocities.add(89);
      }
    }
    return velocities.isEmpty ? [89] : velocities;
  }

  int calculateNotesPerMeasure(
    String timeSignature,
    String rhythmPattern, {
    String? customRhythm,
  }) {
    int beats = 4;
    if (timeSignature != "Auto") {
      int? parsed = int.tryParse(timeSignature.split('/')[0]);
      if (parsed != null && parsed > 0) beats = parsed;
    }
    List<String> pattern =
        parsePatternString(rhythmPattern, customRhythmOverride: customRhythm);
    if (pattern.length == 1) {
      String r = pattern.first;
      if (r == "8th") return beats * 2;
      if (r == "32nd") return beats * 8;
      if (r == "Quarter") return beats;
      return beats * 4;
    }
    return beats * pattern.length;
  }

  List<GpBeat> sequenceToBeats(List<List<int>> rawSequence) {
    List<GpBeat> beats = [];
    for (var notePair in rawSequence) {
      int str = notePair[0];
      int fret = notePair[1];
      if (str == -1 || fret == -1) {
        beats.add(GpBeat.rest(duration: 0.25));
      } else {
        int pitch =
            (str >= 1 && str <= 6) ? (engine.openStrings[str] ?? 40) + fret : 60;
        beats.add(GpBeat.single(GpNote(
          stringNum: str,
          fretNum: fret,
          pitch: pitch,
          duration: 0.25,
        )));
      }
    }
    return beats;
  }
}