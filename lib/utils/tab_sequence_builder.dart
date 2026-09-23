import 'dart:math';
import '../models/lick_preset.dart';
import '../models/motif_token.dart';
import '../scale_engine.dart';

/// Pure-dart utility for calculating note sequences, rhythms, and accents.
class TabSequenceBuilder {
  final ScaleEngine engine;

  TabSequenceBuilder({required this.engine});

  // ── Rhythm & Accent Parsing ────────────────────────────────────────────────

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

  // ── Manual Tab Parser ──────────────────────────────────────────────────────

  /// Parses manual tab syntax "str:fret, str:fret" into a sequence.
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
      List<String> sub = p.split(':');
      if (sub.length == 2) {
        int? s = int.tryParse(sub[0]);
        int? f = int.tryParse(sub[1]);
        if (s != null && f != null && s >= 1 && s <= 8 && f >= 0 && f <= 24) {
          sequence.add([s, f]);
        }
      }
    }
    return sequence;
  }

  // ── Sequence Generation ────────────────────────────────────────────────────

  /// Rebuilds a note sequence precisely as saved in a [LickPreset].
  List<List<int>> buildSequenceForPreset(LickPreset preset) {
    // 1. Initial manual sequence check
    if (preset.system == "Manual Entry") {
      List<List<int>> base = parseManualTab(preset.manualTabString ?? "");
      return engine.applyIntervalBreaks(base, preset.breakInterval, preset.breakLength);
    }

    // 2. Setup environment
    engine.tunings[preset.tuning] ??= engine.openStrings;
    int rootPitch = engine.noteMap[preset.key] ?? 0;
    List<int> formula = engine.scaleFormulas[preset.scale] ?? engine.scaleFormulas["Minor Pentatonic"]!;
    
    // 3. Build Base Dict
    Map<int, List<int>> boxDict;
    if (preset.system == "Single String Horizontal") {
      boxDict = engine.getScaleNotesSingleString(preset.key, preset.scale, preset.startFret, int.tryParse(preset.fragment) ?? 1);
    } else if (preset.system == "3-Note-Per-String (3NPS)") {
      boxDict = engine.getScaleNotes3NPS(preset.key, preset.scale, preset.startFret, [1, 2, 3, 4, 5, 6]);
    } else if (preset.system == "Custom Notes-Per-String") {
      List<int> npsProfile = (preset.customNps).split(',').map((e) => int.tryParse(e.trim()) ?? 3).toList();
      boxDict = engine.getScaleNotesCustomNPS(preset.key, preset.scale, preset.startFret, [1, 2, 3, 4, 5, 6], npsProfile);
    } else {
      boxDict = engine.getScaleNotesBox(preset.key, preset.scale, preset.startFret, [1, 2, 3, 4, 5, 6]);
    }

    // 4. Generate Core Sequence
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
         currentSequence = engine.buildCustomMotif(boxDict, tokens.join(','), 6, 1);
      } else {
         List<List<int>> baseNotes = engine.flattenBoxDict(boxDict, 6, 1);
         if (preset.pathway == "Custom Sequence (Indices)") {
           currentSequence = engine.buildCustomSequence(baseNotes, preset.fragment);
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
      for (int i = 0; i < preset.endRests; i++) currentSequence.add([-1, -1]);
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
    
    // In actual implementation, Auto attempts to group motifs if possible
    // Here we just return a sensible default for visual chunking
    if (parsed.length == 3 && parsed[0] == "8th") return 12; // triplets
    return 16; // default 4/4 16ths
  }
}

