import 'dart:math';

import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/lick_preset.dart';
import '../scale_engine.dart';

/// Pure-dart utility for calculating note sequences, rhythms, and accents.
class TabSequenceBuilder {
  final ScaleEngine engine;

  TabSequenceBuilder({required this.engine});

  // --- Rhythm & Accent Parsing ---

  /// Returns `true` if the accent string signifies auto-generation.
  bool isAutoAccent(String accentStr) =>
      accentStr.toLowerCase().contains("auto");

  /// Parses an accent pattern string (e.g. "1,0,0") into a repeating list of velocities.
  /// 1 maps to 127 (accent), 0 maps to 80 (normal).
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

  /// Parses rhythm patterns into string lists (e.g. `["16th", "8th", "16th"]`).
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

  // --- Manual Tab Parser ---

  /// Parses manual tab syntax "str:fret, str:fret" or chords "str:fret+str:fret" into a sequence.
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
      // Check for chord notation using '+' or '/'
      List<String> noteTokens = (p.contains('+') || p.contains('/'))
          ? p.split(RegExp(r'[+/]'))
          : [p];
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

  /// Parses manual tab syntax into a list of [GpBeat] objects, grouping multiple
  /// strings/frets separated by '+' into a single chord beat.
  List<GpBeat> parseManualTabBeats(String input, {double defaultDuration = 0.25}) {
    List<GpBeat> beats = [];
    List<String> parts = input.split(',');
    for (String p in parts) {
      p = p.trim();
      if (p.isEmpty) continue;
      if (p.toLowerCase() == 'r') {
        beats.add(GpBeat.rest(duration: defaultDuration));
        continue;
      }
      List<String> noteTokens = (p.contains('+') || p.contains('/'))
          ? p.split(RegExp(r'[+/]'))
          : [p];
      List<GpNote> chordNotes = [];
      for (String token in noteTokens) {
        List<String> sub = token.trim().split(':');
        if (sub.length == 2) {
          int? s = int.tryParse(sub[0]);
          int? f = int.tryParse(sub[1]);
          if (s != null && f != null && s >= 1 && s <= 8 && f >= 0 && f <= 24) {
            chordNotes.add(GpNote(
              stringNum: s,
              fretNum: f,
              duration: defaultDuration,
            ));
          }
        }
      }
      if (chordNotes.isNotEmpty) {
        beats.add(GpBeat(notes: chordNotes, duration: defaultDuration));
      }
    }
    return beats;
  }

  /// Converts a flat `List<List<int>>` note sequence into a `List<GpBeat>` list.
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

  // --- Sequence Generation ---

  /// Rebuilds a note sequence precisely as saved in a [LickPreset].
  /// Honors start/end string boundaries and directional orientation.
  List<List<int>> buildSequenceForPreset(
    LickPreset preset, {
    int selectionStart = -1,
    int selectionEnd = -1,
  }) {
    // 1. Initial manual sequence check
    if (preset.system == "Manual Entry") {
      List<List<int>> base = parseManualTab(preset.manualTabString ?? "");
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

    // 2. Setup environment
    engine.tunings[preset.tuning] ??= engine.openStrings;
    
    // Dynamically extract start and end strings honoring orientation
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

    // 3. Build Base Dict explicitly using the restricted target strings
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

    // 4. Generate Core Sequence using boundaries
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
           // Graceful fallback protecting against previous JSON saves where sequence was overwriting fragment bounds
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

    // 5. Apply intervals & rests
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

  /// Calculates notes per measure dynamically (defaults to 16 for Auto).
  int calculateNotesPerMeasure(String timeSig, String rhythm, {String? customRhythm}) {
    if (timeSig != "Auto") {
      final List<String> parts = timeSig.split('/');
      if (parts.length == 2) {
        final int? num = int.tryParse(parts[0]);
        if (num != null && num > 0) return num * 4; 
      }
    }
    
    // Auto calculation based on pattern length vs measures
    List<String> parsed = parsePatternString(rhythm, customRhythmOverride: customRhythm);
    if (parsed.isEmpty) return 16;
    
    if (parsed.length == 3 && parsed[0] == "8th") return 12; // triplets
    return 16; // default 4/4 16ths
  }
}