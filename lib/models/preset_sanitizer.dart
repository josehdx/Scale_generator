import 'lick_preset.dart';

class PresetValidationIssue {
  final String field;
  final String message;
  final bool autoHealed;

  PresetValidationIssue({
    required this.field,
    required this.message,
    this.autoHealed = true,
  });
}

class PresetSanitizer {
  static (LickPreset healedPreset, List<PresetValidationIssue> issues) validateAndSanitize(LickPreset preset) {
    List<PresetValidationIssue> issues = [];
    
    // 1. Calculate expected accent count based on Time Signature or Pathway
    int expectedLength = 4;
    
    if (preset.timeSignature != "Auto") {
      int? parsedSig = int.tryParse(preset.timeSignature.split('/')[0]);
      if (parsedSig != null && parsedSig > 0) {
        expectedLength = parsedSig;
      }
    } else {
      if (preset.system == "Manual Entry") {
        expectedLength = 4;
      } else if (preset.pathway == "3-Step Triplet") {
        expectedLength = 3;
      } else if (preset.pathway == "Custom Motif Builder" && preset.system != "Manual Entry") {
        if (preset.motifString.isNotEmpty) {
          expectedLength = preset.motifString.split(',').where((e) => e.trim().isNotEmpty).length;
        }
      } else if (preset.pathway == "Custom Sequence (Indices)" && preset.system != "Manual Entry") {
        int count = preset.motifString.split(',').where((e) => e.trim().isNotEmpty).length;
        if (count > 0) expectedLength = count;
      }
    }

    String sanitizedAccent = preset.customAccentString;
    List<String> currentAccents = preset.customAccentString.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // 2. Detect Accent Length Mismatch
    if (currentAccents.length != expectedLength) {
      // Check if current accents are in auto-generated format (first beat 1, remaining beats 0)
      bool isAuto = currentAccents.isEmpty || 
          (currentAccents.first == "1" && currentAccents.skip(1).every((e) => e == "0"));
      // Auto-expand/contract accent length
      sanitizedAccent = List.generate(expectedLength, (i) => i == 0 ? "1" : "0").join(",");
      // ONLY report a warning issue if the user had typed a custom non-default accent pattern
      if (!isAuto) {
        issues.add(PresetValidationIssue(
          field: "customAccentString",
          message: "Custom accent pattern length (${currentAccents.length}) did not match sequence length ($expectedLength). Auto-adjusted.",
        ));
      }
    }

    // 3. Validate Interval Break sanity
    int sanitizedBreakLength = preset.breakLength;
    if (preset.breakInterval <= 0 && preset.breakLength > 0) {
      sanitizedBreakLength = 0;
    }

    if (issues.isEmpty && sanitizedBreakLength == preset.breakLength && sanitizedAccent == preset.customAccentString) {
      return (preset, []);
    }

    LickPreset healed = LickPreset(
      id: preset.id,
      name: preset.name,
      key: preset.key,
      scale: preset.scale,
      tuning: preset.tuning,
      system: preset.system,
      fragment: preset.fragment,
      customNps: preset.customNps,
      startFret: preset.startFret,
      pathway: preset.pathway,
      direction: preset.direction,
      motifString: preset.motifString,
      rhythm: preset.rhythm,
      customRhythmString: preset.customRhythmString,
      customAccentString: sanitizedAccent,
      manualTabString: preset.manualTabString,
      timeSignature: preset.timeSignature,
      tempo: preset.tempo,
      measuresPerLine: preset.measuresPerLine,
      breakInterval: preset.breakInterval,
      breakLength: sanitizedBreakLength,
      endRests: preset.endRests,
      tabOutput: preset.tabOutput,
      instrumentIndex: preset.instrumentIndex,
      patternMultiplier: preset.patternMultiplier,
      createdAt: preset.createdAt,
    );

    return (healed, issues);
  }

  /// Makes a preset that came from disk / import / an old app version safe to
  /// load: every dropdown value must exist in its option list, numbers are
  /// clamped to the ranges the UI offers, and string fields cannot crash the
  /// parsers. Unknown values fall back to the first option / a default.
  static LickPreset sanitizeFields(
    LickPreset p, {
    required Set<String> keys,
    required Set<String> scales,
    required Set<String> tunings,
    required Set<String> systems,
    required Set<String> pathways,
    required Set<String> directions,
    required Set<String> timeSignatures,
    required Set<String> rhythms,
    required Set<int> instrumentIndexes,
  }) {
    String pick(String v, Set<String> options, String fallback) =>
        options.contains(v) ? v : (options.contains(fallback) ? fallback : options.first);

    // "start-end" strings (1..6), or a single string number for Single String.
    String fragment = p.fragment;
    if (p.system == "Single String Horizontal") {
      fragment = (int.tryParse(fragment) ?? 1).clamp(1, 6).toString();
    } else if (fragment.contains('-')) {
      final parts = fragment.split('-');
      final a = (int.tryParse(parts[0].trim()) ?? 6).clamp(1, 6);
      final b = (parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 1) : 1).clamp(1, 6);
      fragment = "$a-$b";
    }

    return p.copyWith(
      key: pick(p.key, keys, "C"),
      scale: pick(p.scale, scales, "Minor Pentatonic"),
      tuning: pick(p.tuning, tunings, "Standard E"),
      system: pick(p.system, systems, "Box Position / CAGED"),
      pathway: pick(p.pathway, pathways, "Straight Linear"),
      direction: pick(p.direction, directions, "Ascend -> Descend"),
      timeSignature: pick(p.timeSignature, timeSignatures, "Auto"),
      rhythm: pick(p.rhythm, rhythms, "Straight 16ths"),
      fragment: fragment,
      tempo: p.tempo.clamp(40, 300),
      startFret: p.startFret.clamp(0, 24),
      measuresPerLine: p.measuresPerLine.clamp(0, 16),
      breakInterval: p.breakInterval.clamp(0, 64),
      breakLength: p.breakLength.clamp(0, 32),
      endRests: p.endRests.clamp(0, 64),
      patternMultiplier: p.patternMultiplier.clamp(1, 32),
      instrumentIndex: instrumentIndexes.contains(p.instrumentIndex) ? p.instrumentIndex : instrumentIndexes.first,
      customNps: p.customNps.trim().isEmpty ? "3,3,3,3,3,3" : p.customNps,
      customAccentString: p.customAccentString.trim().isEmpty ? "1,0,0,0" : p.customAccentString,
      customRhythmString: p.customRhythmString.trim().isEmpty ? "16,16,8" : p.customRhythmString,
    );
  }
}
