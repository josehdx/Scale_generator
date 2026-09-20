import 'dart:math';

class ScaleEngine {
  final Map<String, int> noteMap = {
    'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
    'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11
  };

  final Map<String, List<int>> scaleFormulas = {
    'Minor Pentatonic': [0, 3, 5, 7, 10],
    'Major Pentatonic': [0, 2, 4, 7, 9],
    'Blues Scale': [0, 3, 5, 6, 7, 10],
    'Natural Minor': [0, 2, 3, 5, 7, 8, 10],
    'Major (Ionian)': [0, 2, 4, 5, 7, 9, 11],
    'Harmonic Minor': [0, 2, 3, 5, 7, 8, 11],
    'Melodic Minor': [0, 2, 3, 5, 7, 9, 11],
    'Harmonic Major': [0, 2, 4, 5, 7, 8, 11],
    'Phrygian Dominant': [0, 1, 4, 5, 7, 8, 10],
    'Dorian': [0, 2, 3, 5, 7, 9, 10],
    'Mixolydian': [0, 2, 4, 5, 7, 9, 10]
  };

  Map<int, int> openStrings = {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40};

  final Map<String, Map<int, int>> tunings = {
    'Standard E': {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40},
    'Drop D': {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 38},
    'Eb Standard': {1: 63, 2: 58, 3: 54, 4: 49, 5: 44, 6: 39},
    'D Standard': {1: 62, 2: 57, 3: 53, 4: 48, 5: 43, 6: 38},
  };

  void setTuning(String tuningName) {
    if (tunings.containsKey(tuningName)) {
      openStrings = tunings[tuningName]!;
    }
  }

  Map<int, List<int>> getScaleNotesBox(
      String key, String scale, int startFret, List<int> targetStrings) {
    int rootPc = noteMap[key] ?? 0;
    List<int> formula = scaleFormulas[scale] ?? [0, 2, 4, 5, 7, 9, 11];
    List<int> scalePcs = formula.map((step) => (rootPc + step) % 12).toList();
    Map<int, List<int>> boxDict = {};

    for (int stringNum in targetStrings..sort((a, b) => b.compareTo(a))) {
      int openMidi = openStrings[stringNum]!;
      List<int> stringFrets = [];
      for (int fret = startFret; fret < startFret + 4; fret++) {
        int pitch = openMidi + fret;
        if (scalePcs.contains(pitch % 12)) {
          stringFrets.add(fret);
        }
      }
      boxDict[stringNum] = stringFrets;
    }
    return boxDict;
  }

  Map<int, List<int>> getScaleNotes3NPS(
      String key, String scale, int startFret, List<int> targetStrings) {
    int rootPc = noteMap[key] ?? 0;
    List<int> formula = scaleFormulas[scale] ?? [0, 2, 4, 5, 7, 9, 11];
    List<int> scalePcs = formula.map((step) => (rootPc + step) % 12).toList();
    Map<int, List<int>> boxDict = {};
    int lastMinPitch = -1;

    for (int stringNum in targetStrings..sort((a, b) => b.compareTo(a))) {
      int openMidi = openStrings[stringNum]!;
      List<int> stringFrets = [];
      int fret = (lastMinPitch != -1) ? max(0, lastMinPitch + 1 - openMidi) : startFret;

      while (stringFrets.length < 3 && fret < 24) {
        int pitch = openMidi + fret;
        if (scalePcs.contains(pitch % 12) && pitch > lastMinPitch) {
          stringFrets.add(fret);
          lastMinPitch = pitch;
        }
        fret++;
      }
      boxDict[stringNum] = stringFrets;
    }
    return boxDict;
  }

  Map<int, List<int>> getScaleNotesSingleString(
      String key, String scale, int startFret, int targetString) {
    int rootPc = noteMap[key] ?? 0;
    List<int> formula = scaleFormulas[scale] ?? [0, 2, 4, 5, 7, 9, 11];
    List<int> scalePcs = formula.map((step) => (rootPc + step) % 12).toList();
    int openMidi = openStrings[targetString]!;
    List<int> stringFrets = [];

    for (int fret = startFret; fret < min(startFret + 12, 24); fret++) {
      int pitch = openMidi + fret;
      if (scalePcs.contains(pitch % 12)) {
        stringFrets.add(fret);
      }
    }
    return {targetString: stringFrets};
  }

  List<List<int>> flattenBoxDict(Map<int, List<int>> boxDict) {
    List<List<int>> flatNotes = [];
    int lastPitch = -1;
    List<int> sortedStrings = boxDict.keys.toList()..sort((a, b) => b.compareTo(a));

    for (int s in sortedStrings) {
      List<int> frets = boxDict[s] ?? [];
      for (int f in frets) {
        int pitch = openStrings[s]! + f;
        if (pitch > lastPitch) {
          flatNotes.add([s, f]);
          lastPitch = pitch;
        }
      }
    }
    return flatNotes;
  }

  List<List<int>> apply3StepSequence(List<List<int>> baseNotes) {
    if (baseNotes.length < 3) return baseNotes;
    List<List<int>> result = [];
    for (int i = 0; i < baseNotes.length - 2; i++) {
      result.addAll([baseNotes[i], baseNotes[i + 1], baseNotes[i + 2]]);
    }
    return result;
  }

  List<List<int>> apply4StepSequence(List<List<int>> baseNotes) {
    if (baseNotes.length < 4) return baseNotes;
    List<List<int>> result = [];
    for (int i = 0; i < baseNotes.length - 3; i++) {
      result.addAll([baseNotes[i], baseNotes[i + 1], baseNotes[i + 2], baseNotes[i + 3]]);
    }
    return result;
  }

  List<List<int>> applyNoteSkipping(List<List<int>> baseNotes) {
    if (baseNotes.length < 3) return baseNotes;
    List<List<int>> result = [];
    for (int i = 0; i < baseNotes.length - 2; i++) {
      result.addAll([baseNotes[i], baseNotes[i + 2]]);
    }
    return result;
  }

  List<List<int>> buildCustomMotif(
      Map<int, List<int>> boxDict, String motifStr, String pairDirection) {
    List<List<int>> result = [];
    List<String> tokens = motifStr
        .split(',')
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toList();

    if (tokens.isEmpty) return result;

    List<int> availableStrings = boxDict.keys.toList()..sort();
    if (availableStrings.length < 2) return result;

    List<List<int>> stringPairs = [];
    if (pairDirection.startsWith("Descend")) {
      for (int i = 1; i < availableStrings.length; i++) {
        stringPairs.add([availableStrings[i], availableStrings[i - 1]]);
      }
    } else {
      for (int i = availableStrings.length - 1; i > 0; i--) {
        stringPairs.add([availableStrings[i], availableStrings[i - 1]]);
      }
    }

    for (var pair in stringPairs) {
      int lowerStr = pair[0];
      int higherStr = pair[1];

      List<int> lowNotes = boxDict[lowerStr] ?? [];
      List<int> highNotes = boxDict[higherStr] ?? [];

      if (lowNotes.isEmpty || highNotes.isEmpty) continue;

      for (String token in tokens) {
        if (token.startsWith('L')) {
          int idx = (int.tryParse(token.substring(1)) ?? 1) - 1;
          if (idx >= 0 && idx < lowNotes.length) {
            result.add([lowerStr, lowNotes[idx]]);
          }
        } else if (token.startsWith('H')) {
          int idx = (int.tryParse(token.substring(1)) ?? 1) - 1;
          if (idx >= 0 && idx < highNotes.length) {
            result.add([higherStr, highNotes[idx]]);
          }
        }
      }
    }
    return result;
  }

  List<List<int>> applyIntervalBreaks(
      List<List<int>> sequence, int interval, int breakLen) {
    if (interval <= 0 || breakLen <= 0 || sequence.isEmpty) return sequence;

    List<List<int>> result = [];
    for (int i = 0; i < sequence.length; i++) {
      result.add(sequence[i]);
      if ((i + 1) % interval == 0) {
        for (int b = 0; b < breakLen; b++) {
          result.add([-1, -1]);
        }
      }
    }
    return result;
  }

  String renderAsciiTab(
    List<List<int>> noteSequence, {
    String rhythmStr = "16th",
    int measuresPerSystem = 1,
    int beatsPerMeasure = 4,
    int tempo = 120,
  }) {
    int multiplier = {"Quarter": 1, "8th": 2, "16th": 4}[rhythmStr] ?? 4;
    int notesPerMeasure = beatsPerMeasure * multiplier;
    int activeMeasuresPerLine = measuresPerSystem <= 0 ? 999 : measuresPerSystem;
    int notesPerSystem = notesPerMeasure * activeMeasuresPerLine;

    Map<int, String> stringLabels = {1: 'e', 2: 'B', 3: 'G', 4: 'D', 5: 'A', 6: 'E'};
    List<String> outputLines = [
      "Tempo: $tempo BPM",
      "Time Signature: $beatsPerMeasure/4",
      "Rhythm: $rhythmStr notes",
      ""
    ];

    for (int sysStart = 0; sysStart < noteSequence.length; sysStart += notesPerSystem) {
      int sysEnd = min(sysStart + notesPerSystem, noteSequence.length);
      List<List<int>> systemNotes = noteSequence.sublist(sysStart, sysEnd);

      Map<int, String> systemGrid = {for (int s = 1; s <= 6; s++) s: "${stringLabels[s]}|"};

      for (int idx = 0; idx < systemNotes.length; idx++) {
        var note = systemNotes[idx];
        int strNum = note[0];
        int fret = note[1];

        if (idx > 0 && idx % notesPerMeasure == 0) {
          for (int s = 1; s <= 6; s++) {
            systemGrid[s] = "${systemGrid[s]}|";
          }
        }

        int colWidth = (strNum != -1 && fret >= 10) ? 4 : 3;

        for (int s = 1; s <= 6; s++) {
          if (s == strNum) {
            systemGrid[s] = "${systemGrid[s]}-$fret-";
          } else {
            systemGrid[s] = systemGrid[s]! + ("-" * colWidth);
          }
        }
      }

      for (int s = 1; s <= 6; s++) {
        systemGrid[s] = "${systemGrid[s]}|";
        outputLines.add(systemGrid[s]!);
      }
      outputLines.add("");
    }

    return outputLines.join("\n");
  }
}