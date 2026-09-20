class ScaleEngine {
  // MUSIC THEORY DATA
  final Map<String, int> noteMap = {
    "C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
    "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11
  };

  final Map<String, List<int>> scaleFormulas = {
    "Minor Pentatonic": [0, 3, 5, 7, 10],
    "Major Pentatonic": [0, 2, 4, 7, 9],
    "Blues Scale": [0, 3, 5, 6, 7, 10],
    "Natural Minor": [0, 2, 3, 5, 7, 8, 10],
    "Major (Ionian)": [0, 2, 4, 5, 7, 9, 11],
    "Harmonic Minor": [0, 2, 3, 5, 7, 8, 11],
    "Melodic Minor": [0, 2, 3, 5, 7, 9, 11],
    "Harmonic Major": [0, 2, 4, 5, 7, 8, 11],
    "Phrygian Dominant": [0, 1, 4, 5, 7, 8, 10],
    "Dorian": [0, 2, 3, 5, 7, 9, 10],
    "Mixolydian": [0, 2, 4, 5, 7, 9, 10]
  };

  // TUNING ARCHITECTURE (Upgraded to Absolute MIDI Pitches for Audio)
  final Map<String, Map<int, int>> tunings = {
    "Standard E": {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40},
    "Drop D": {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 38},
    "Eb (Half-Step Down)": {1: 63, 2: 58, 3: 54, 4: 49, 5: 44, 6: 39},
    "D Standard": {1: 62, 2: 57, 3: 53, 4: 48, 5: 43, 6: 38},
    "DADGAD": {1: 62, 2: 57, 3: 55, 4: 50, 5: 45, 6: 38},
  };

  Map<int, int> openStrings = {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40};

  void setTuning(String tuningName) {
    if (tunings.containsKey(tuningName)) {
      openStrings = Map<int, int>.from(tunings[tuningName]!);
    }
  }

  List<int> getScalePitchClasses(String rootName, String scaleType) {
    int rootPitch = noteMap[rootName]!;
    List<int> formula = scaleFormulas[scaleType]!;
    return formula.map((interval) => (rootPitch + interval) % 12).toList();
  }

  // SYSTEM GENERATORS
  Map<int, List<int>> getScaleNotesBox(String rootName, String scaleType, int startFret, List<int> targetStrings) {
    Set<int> scalePcs = getScalePitchClasses(rootName, scaleType).toSet();
    Map<int, List<int>> boxDict = {};
    for (int stringNum in targetStrings) {
      int openPitch = openStrings[stringNum]!;
      List<int> frets = [];
      for (int fret = startFret; fret < startFret + 5; fret++) { 
        if (scalePcs.contains((openPitch + fret) % 12)) frets.add(fret);
      }
      if (frets.isNotEmpty) boxDict[stringNum] = frets;
    }
    return boxDict;
  }

  Map<int, List<int>> getScaleNotes3NPS(String rootName, String scaleType, int startFret, List<int> targetStrings) {
    Set<int> scalePcs = getScalePitchClasses(rootName, scaleType).toSet();
    Map<int, List<int>> boxDict = {};
    for (int stringNum in targetStrings) {
      int openPitch = openStrings[stringNum]!;
      List<int> frets = [];
      for (int fret = startFret; fret < startFret + 15; fret++) {
        if (scalePcs.contains((openPitch + fret) % 12)) {
          frets.add(fret);
          if (frets.length == 3) break; 
        }
      }
      if (frets.isNotEmpty) boxDict[stringNum] = frets;
    }
    return boxDict;
  }

  Map<int, List<int>> getScaleNotesSingleString(String rootName, String scaleType, int startFret, int targetString) {
    Set<int> scalePcs = getScalePitchClasses(rootName, scaleType).toSet();
    int openPitch = openStrings[targetString]!;
    List<int> frets = [];
    for (int fret = startFret; fret < startFret + 13; fret++) {
      if (scalePcs.contains((openPitch + fret) % 12)) frets.add(fret);
    }
    return {targetString: frets};
  }

  // FLATTEN DICT TO SEQUENCE
  List<List<int>> flattenBoxDict(Map<int, List<int>> boxDict) {
    List<List<int>> sequence = [];
    List<int> strings = boxDict.keys.toList()..sort((a, b) => b.compareTo(a));
    for (int s in strings) {
      for (int f in boxDict[s]!) {
        sequence.add([s, f]);
      }
    }
    return sequence;
  }

  // NON-LINEAR PATHWAY SEQUENCERS
  List<List<int>> apply3StepSequence(List<List<int>> notes) {
    List<List<int>> seq = [];
    for (int i = 0; i < notes.length - 2; i++) {
      seq.addAll([notes[i], notes[i + 1], notes[i + 2]]);
    }
    return seq;
  }

  List<List<int>> apply4StepSequence(List<List<int>> notes) {
    List<List<int>> seq = [];
    for (int i = 0; i < notes.length - 3; i++) {
      seq.addAll([notes[i], notes[i + 1], notes[i + 2], notes[i + 3]]);
    }
    return seq;
  }

  List<List<int>> applyNoteSkipping(List<List<int>> notes) {
    List<List<int>> seq = [];
    for (int i = 0; i < notes.length - 2; i++) {
      seq.addAll([notes[i], notes[i + 2]]);
    }
    return seq;
  }

  // CUSTOM MOTIF BUILDER
  List<List<int>> buildCustomMotif(Map<int, List<int>> boxDict, String rawMotif, String pairDirection) {
    List<int> availableStrings = boxDict.keys.toList()..sort();
    if (availableStrings.length < 2) return [];

    List<List<int>> pairs = [];
    if (pairDirection == "Descend (High -> Low)") { 
      for (int i = 1; i < availableStrings.length; i++) {
        pairs.add([availableStrings[i], availableStrings[i - 1]]); 
      }
    } else { 
      for (int i = availableStrings.length - 1; i > 0; i--) {
        pairs.add([availableStrings[i], availableStrings[i - 1]]); 
      }
    }

    List<Map<String, dynamic>> tokens = [];
    List<String> parts = rawMotif.split(',').where((p) => p.trim().isNotEmpty).toList();
    for (String p in parts) {
      p = p.trim().toUpperCase();
      if (p.length < 2) continue;
      String side = p[0];
      int? idx = int.tryParse(p.substring(1));
      if (idx != null && idx > 0 && (side == 'L' || side == 'H')) {
        tokens.add({'side': side, 'idx': idx - 1});
      }
    }

    List<List<int>> sequence = [];
    for (var pair in pairs) {
      int lowStr = pair[0];
      int highStr = pair[1];
      for (var t in tokens) {
        int targetStr = (t['side'] == 'L') ? lowStr : highStr;
        List<int>? frets = boxDict[targetStr];
        if (frets != null && frets.isNotEmpty) {
          int safeIdx = t['idx'].clamp(0, frets.length - 1);
          sequence.add([targetStr, frets[safeIdx]]);
        }
      }
    }
    return sequence;
  }

  // INTERVAL BREAK LOGIC
  List<List<int>> applyIntervalBreaks(List<List<int>> sequence, int breakInterval, int breakLength) {
    if (breakInterval <= 0) return sequence;
    
    List<List<int>> newPattern = [];
    for (int i = 0; i < sequence.length; i++) {
      newPattern.add(sequence[i]);
      if ((i + 1) % breakInterval == 0 && (i + 1) < sequence.length) {
        for (int j = 0; j < breakLength; j++) {
          newPattern.add([-1, -1]); 
        }
      }
    }
    return newPattern;
  }

  // ASCII TAB RENDERER WITH METADATA HEADER
  String renderAsciiTab(
    List<List<int>> noteSequence, {
    int spacing = 2, 
    int margin = 2,
    String rhythmStr = "16th",
    int measuresPerSystem = 2,
    int beatsPerMeasure = 4,
    int tempo = 120,
  }) {
    Map<String, int> multiplierMap = {"Quarter": 1, "8th": 2, "16th": 4};
    int multiplier = multiplierMap[rhythmStr] ?? 4;
    
    int notesPerMeasure = beatsPerMeasure * multiplier;
    int notesPerSystem = notesPerMeasure * measuresPerSystem;

    Map<int, String> stringHeaders = {1: "e|", 2: "B|", 3: "G|", 4: "D|", 5: "A|", 6: "E|"};
    
    List<String> outputLines = [
      "Tempo: $tempo BPM",
      "Time Signature: $beatsPerMeasure/4",
      "Rhythm: $rhythmStr notes",
      ""
    ];

    for (int sysStart = 0; sysStart < noteSequence.length; sysStart += notesPerSystem) {
      int end = sysStart + notesPerSystem;
      if (end > noteSequence.length) end = noteSequence.length;
      List<List<int>> systemNotes = noteSequence.sublist(sysStart, end);

      Map<int, StringBuffer> rows = {
        for (var s in [1, 2, 3, 4, 5, 6]) s: StringBuffer(stringHeaders[s]! + ("-" * margin))
      };

      for (int i = 0; i < systemNotes.length; i++) {
        if (i > 0 && i % notesPerMeasure == 0) {
          for (int s = 1; s <= 6; s++) {
            rows[s]!.write("|");
          }
        }

        int activeStr = systemNotes[i][0];
        int fretVal = systemNotes[i][1];

        if (activeStr == -1) {
          for (int s = 1; s <= 6; s++) {
            rows[s]!.write("-" * (spacing + 2));
          }
        } else {
          String fretStr = fretVal.toString();
          int totalSlotLen = fretStr.length + spacing;

          for (int s = 1; s <= 6; s++) {
            if (s == activeStr) {
              rows[s]!.write(fretStr + ("-" * spacing));
            } else {
              rows[s]!.write("-" * totalSlotLen);
            }
          }
        }
      }

      for (int s = 1; s <= 6; s++) {
        rows[s]!.write("|");
        outputLines.add(rows[s]!.toString());
      }
      outputLines.add(""); 
    }

    return outputLines.join("\n");
  }
}