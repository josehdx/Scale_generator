import 'dart:math';
import '../models/gp_beat.dart';
import '../models/gp_note.dart';
import '../models/lick_preset.dart';
import '../scale_engine.dart';


/// Pure-Dart utility for the studio: note sequences, rhythms and accents.
/// (The Guitar Pro timeline lives in gp_timeline.dart.)
class TabSequenceBuilder {
  final ScaleEngine engine;
  TabSequenceBuilder({required this.engine});

  static double roundMs(double ms) {
    return (ms * 10).round() / 10.0;
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

  static final RegExp _manualNote = RegExp(r'^(\d+)\s*:\s*(\d+)\s*(?:\(\s*([8qQ])\s*\))?$');
  static final RegExp _manualRest = RegExp(r'^r\s*(?:\(\s*([8qQ])\s*\))?$', caseSensitive: false);

  /// 0 = pattern default (16th), 1 = eighth, 2 = quarter.
  static int _durationCode(String? marker) => marker == null ? 0 : (marker == '8' ? 1 : 2);

  /// Beats of a per-note duration code (null = use the rhythm pattern).
  static double? durationCodeToBeats(int code) => code == 1 ? 0.5 : (code == 2 ? 1.0 : null);

  /// The comma separated tokens of a manual tab, exactly as
  /// [parseManualTab] counts them (blank entries ignored).
  static List<String> manualTokens(String input) =>
      input.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// Parses manual entry text such as `6:5, 6:8(8), r, 5:7+4:7`.
  ///
  /// Every entry is `[string, fret, durationCode, tokenIndex]` (rests use
  /// string/fret -1). `tokenIndex` is the position of the source token in
  /// [manualTokens], which lets the UI map a selection in the expanded
  /// sequence back to the text. Strings are 1..6.
  List<List<int>> parseManualTab(String input) {
    final List<List<int>> sequence = [];
    final List<String> tokens = manualTokens(input);
    for (int t = 0; t < tokens.length; t++) {
      final String p = tokens[t];
      final RegExpMatch? rest = _manualRest.firstMatch(p);
      if (rest != null) {
        sequence.add([-1, -1, _durationCode(rest.group(1)), t]);
        continue;
      }
      final List<String> noteTokens = (p.contains('+') || p.contains('/')) ? p.split(RegExp(r'[+/]')) : [p];
      for (final String token in noteTokens) {
        final RegExpMatch? m = _manualNote.firstMatch(token.trim());
        if (m == null) continue;
        final int s = int.parse(m.group(1)!);
        final int f = int.parse(m.group(2)!);
        if (s >= 1 && s <= 6 && f >= 0 && f <= 24) {
          sequence.add([s, f, _durationCode(m.group(3)), t]);
        }
      }
    }
    return sequence;
  }

  List<GpBeat> sequenceToBeats(List<List<int>> sequence, {double defaultDuration = 0.25}) {
    return sequence.map((note) {
      final double dur = (note.length > 2 ? durationCodeToBeats(note[2]) : null) ?? defaultDuration;
      if (note[0] == -1 || note[1] == -1) {
        return GpBeat.rest(duration: dur);
      }
      return GpBeat.single(
        GpNote(stringNum: note[0], fretNum: note[1], duration: dur),
        duration: dur,
      );
    }).toList();
  }

  List<List<int>> _applyPatternMultiplier(List<List<int>> sequence, LickPreset preset) {
    if (preset.patternMultiplier <= 1 || sequence.isEmpty) return sequence;

    int chunkSize = 4;
    if (preset.timeSignature != "Auto") {
      int? parsedSig = int.tryParse(preset.timeSignature.split('/')[0]);
      if (parsedSig != null && parsedSig > 0) chunkSize = parsedSig;
    } else {
      if (preset.system == "Manual Entry") {
        chunkSize = 4;
      } else if (preset.pathway == "3-Step Triplet") {
        chunkSize = 3;
      } else if (preset.pathway == "Custom Motif Builder" && preset.system != "Manual Entry" && preset.motifString.isNotEmpty) {
        chunkSize = preset.motifString.split(',').where((e) => e.trim().isNotEmpty).length;
      } else if (preset.pathway == "Custom Sequence (Indices)" && preset.system != "Manual Entry") {
        int count = preset.motifString.split(',').where((e) => e.trim().isNotEmpty).length;
        if (count > 0) chunkSize = count;
      }
    }

    List<List<int>> multiplied = [];
    for (int i = 0; i < sequence.length; i += chunkSize) {
      List<List<int>> chunk = sequence.sublist(i, min(i + chunkSize, sequence.length));
      for (int m = 0; m < preset.patternMultiplier; m++) {
        multiplied.addAll(chunk);
      }
    }
    return multiplied;
  }

  List<List<int>> buildSequenceForPreset(
    LickPreset preset, {
    int selectionStart = -1,
    int selectionEnd = -1,
  }) {
    // Generate in the preset's own tuning. The engine used to be switched only
    // inside the fretboard widget's build(), i.e. AFTER the tab was generated.
    engine.setTuning(preset.tuning);

    if (preset.system == "Manual Entry") {
      List<List<int>> base = parseManualTab(preset.manualTabString);
      base = _applyPatternMultiplier(base, preset);
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
      boxDict = engine.getScaleNotes3NPS(preset.key, preset.scale, preset.startFret, targetStrings.isEmpty ? [1, 2, 3, 4, 5, 6] : targetStrings);
    } else if (preset.system == "Custom Notes-Per-String") {
      List<int> npsProfile = (preset.customNps).split(',').map((e) => int.tryParse(e.trim()) ?? 3).toList();
      boxDict = engine.getScaleNotesCustomNPS(preset.key, preset.scale, preset.startFret, targetStrings.isEmpty ? [1, 2, 3, 4, 5, 6] : targetStrings, npsProfile);
    } else {
      boxDict = engine.getScaleNotesBox(preset.key, preset.scale, preset.startFret, targetStrings.isEmpty ? [1, 2, 3, 4, 5, 6] : targetStrings);
    }

    List<List<int>> currentSequence = [];

    if (preset.system == "Single String Horizontal") {
      final int target = (int.tryParse(preset.fragment) ?? 1).clamp(1, 6);
      final List<List<int>> base = engine.flattenBoxDict(boxDict, target, target);
      final bool descending = preset.direction == "Descend -> Ascend" || preset.direction == "One-Way (Descend)";

      List<List<int>> motif = [];
      if (preset.pathway == "Custom Motif Builder") {
        // The motif builder handles the direction itself.
        motif = engine.buildSingleStringMotif(boxDict, preset.motifString, target, preset.direction);
      }
      if (motif.isNotEmpty) {
        currentSequence = motif;
      } else {
        List<List<int>> patternNotes;
        if (preset.pathway == "Custom Sequence (Indices)") {
          patternNotes = engine.buildCustomSequence(base, preset.motifString.isNotEmpty ? preset.motifString : preset.fragment);
        } else if (preset.pathway == "3-Step Triplet") {
          patternNotes = engine.apply3StepSequence(base);
        } else if (preset.pathway == "4-Step 16th") {
          patternNotes = engine.apply4StepSequence(base);
        } else if (preset.pathway == "Note Skipping") {
          patternNotes = engine.applyNoteSkipping(base);
        } else {
          patternNotes = base;
        }
        currentSequence = descending ? patternNotes.reversed.toList() : patternNotes;
      }
    } else {
      List<List<int>> patternNotes;
      
      if (preset.pathway == "Custom Motif Builder") {
        List<String> tokens = (preset.motifString).split(',').where((s) => s.isNotEmpty).toList();
        patternNotes = engine.buildCustomMotif(boxDict, tokens.join(','), stStr, enStr);
      } else {
        List<List<int>> baseNotes = engine.flattenBoxDict(boxDict, stStr, enStr);
        if (preset.pathway == "Custom Sequence (Indices)") {
          String sequenceStr = preset.motifString.isNotEmpty ? preset.motifString : preset.fragment;
          patternNotes = engine.buildCustomSequence(baseNotes, sequenceStr);
        } else {
          if (preset.pathway == "3-Step Triplet") patternNotes = engine.apply3StepSequence(baseNotes);
          else if (preset.pathway == "4-Step 16th") patternNotes = engine.apply4StepSequence(baseNotes);
          else if (preset.pathway == "Note Skipping") patternNotes = engine.applyNoteSkipping(baseNotes);
          else patternNotes = baseNotes;
        }
      }

      if (preset.direction.startsWith("One-Way")) {
        currentSequence = patternNotes;
      } else {
        currentSequence = [...patternNotes, ...patternNotes.reversed.skip(1).toList()];
      }
    }

    if (currentSequence.isNotEmpty) {
      currentSequence = _applyPatternMultiplier(currentSequence, preset);
      
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

  static double _beatsOf(String rhythm) =>
      const {"Quarter": 1.0, "8th": 0.5, "16th": 0.25, "32nd": 0.125}[rhythm] ?? 0.25;

  int _notesInBeats(List<String> pattern, int beats) {
    if (pattern.isEmpty || beats <= 0) return 16;
    double acc = 0.0;
    int n = 0;
    while (acc < beats - 1e-6 && n < 512) {
      acc += _beatsOf(pattern[n % pattern.length]);
      n++;
    }
    return max(1, n);
  }

  /// Notes in one bar for ANY rhythm pattern (it used to be right only for
  /// 16ths: Straight 8ths in 4/4 is 8 notes, not 16).
  ///
  /// * explicit time signature `x/4`: the notes that fill x beats;
  /// * Auto with [autoNotes] (motif / triplet / index sequence): one bar per
  ///   cycle of that many notes;
  /// * Auto otherwise: 4 beats.
  int calculateNotesPerMeasure(String timeSig, String rhythm, {String? customRhythm, int? autoNotes}) {
    final List<String> pattern = parsePatternString(rhythm, customRhythmOverride: customRhythm);
    if (timeSig != "Auto") {
      final List<String> parts = timeSig.split('/');
      final int? num = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
      if (num != null && num > 0) return _notesInBeats(pattern, num);
    }
    if (autoNotes != null && autoNotes > 0) return autoNotes;
    return _notesInBeats(pattern, 4);
  }

  /// Real notes per second of a pattern at [tempo] (quarter-note BPM).
  double notesPerSecond(int tempo, List<String> pattern) {
    if (pattern.isEmpty || tempo <= 0) return 0.0;
    double beats = 0.0;
    for (final String p in pattern) {
      beats += _beatsOf(p);
    }
    return beats <= 0 ? 0.0 : (tempo / 60.0) * pattern.length / beats;
  }
}