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

    // Detect Accent Length Mismatch
    if (currentAccents.length != expectedLength) {
      bool isAuto = currentAccents.isNotEmpty && currentAccents.first == "1" && currentAccents.skip(1).every((e) => e == "0");
      
      if (isAuto || currentAccents.length < expectedLength) {
        sanitizedAccent = List.generate(expectedLength, (i) => i == 0 ? "1" : "0").join(",");
        issues.add(PresetValidationIssue(
          field: "customAccentString",
          message: "Accent pattern length (${currentAccents.length}) did not match sequence length ($expectedLength). Auto-expanded.",
        ));
      }
    }

    // 2. Validate Interval Break sanity (SILENT HEAL)
    int sanitizedBreakLength = preset.breakLength;
    if (preset.breakInterval <= 0 && preset.breakLength > 0) {
      sanitizedBreakLength = 0; // Quietly fix the legacy default state without warning the user
    }

    // Return original if healthy
    if (issues.isEmpty && sanitizedBreakLength == preset.breakLength) {
      return (preset, []);
    }

    // Construct repaired preset
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
      createdAt: preset.createdAt,
    );

    return (healed, issues);
  }
}