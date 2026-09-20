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
    if (tunings.containsKey(tuningName)) openStrings = tunings[tuningName]!;
  }

  Map<int, List<int>> getScaleNotesBox(String key, String scale, int startFret, List<int> targetStrings) {
    int rootPc = noteMap[key] ?? 0;
    List<int> scalePcs = (scaleFormulas[scale] ?? []).map((step) => (rootPc + step) % 12).toList();
    Map<int, List<int>> boxDict = {};

    for (int stringNum in targetStrings) {
      int openMidi = openStrings[stringNum]!;
      List<int> stringFrets = [];
      for (int fret = startFret; fret < startFret + 4; fret++) {
        if (fret <= 24 && scalePcs.contains((openMidi + fret) % 12)) stringFrets.add(fret);
      }
      boxDict[stringNum] = stringFrets;
    }
    return boxDict;
  }

  Map<int, List<int>> getScaleNotes3NPS(String key, String scale, int startFret, List<int> targetStrings) {
    return _buildAscendingNPSBox(key, scale, startFret, targetStrings, List.filled(6, 3));
  }

  Map<int, List<int>> getScaleNotesCustomNPS(String key, String scale, int startFret, List<int> targetStrings, List<int> npsProfile) {
    return _buildAscendingNPSBox(key, scale, startFret, targetStrings, npsProfile);
  }

  Map<int, List<int>> _buildAscendingNPSBox(String key, String scale, int startFret, List<int> targetStrings, List<int> npsProfile) {
    int rootPc = noteMap[key] ?? 0;
    List<int> scalePcs = (scaleFormulas[scale] ?? []).map((step) => (rootPc + step) % 12).toList();
    Map<int, List<int>> boxDict = {};
    int lastMinPitch = -1;

    for (int stringNum in targetStrings..sort((a, b) => b.compareTo(a))) {
      int openMidi = openStrings[stringNum]!;
      List<int> stringFrets = [];
      int fret = (lastMinPitch != -1) ? max(0, lastMinPitch + 1 - openMidi) : startFret;
      int targetNotes = npsProfile.length == 6 ? npsProfile[stringNum - 1] : 3;

      while (stringFrets.length < targetNotes && fret <= 24) {
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

  Map<int, List<int>> getScaleNotesSingleString(String key, String scale, int startFret, int targetString) {
    int rootPc = noteMap[key] ?? 0;
    List<int> scalePcs = (scaleFormulas[scale] ?? []).map((step) => (rootPc + step) % 12).toList();
    int openMidi = openStrings[targetString]!;
    List<int> stringFrets = [];

    int upperFretLimit = min(startFret + 15, 24);
    for (int fret = startFret; fret <= upperFretLimit; fret++) {
      if (scalePcs.contains((openMidi + fret) % 12)) stringFrets.add(fret);
    }
    return {targetString: stringFrets};
  }

  // UPDATED: Now strictly follows the exact start/end string numbers passed by the UI
  List<List<int>> flattenBoxDict(Map<int, List<int>> boxDict, int startStr, int endStr) {
    List<List<int>> flatNotes = [];
    
    if (startStr >= endStr) { 
      // Ascending pitch (e.g. 6 down to 1)
      int lastPitch = -1;
      for (int s = startStr; s >= endStr; s--) {
        List<int> frets = (boxDict[s] ?? []).toList()..sort();
        for (int f in frets) {
          int pitch = openStrings[s]! + f;
          if (pitch > lastPitch) {
            flatNotes.add([s, f]);
            lastPitch = pitch;
          }
        }
      }
    } else { 
      // Descending pitch (e.g. 1 up to 6)
      int lastPitch = 999;
      for (int s = startStr; s <= endStr; s++) {
        List<int> frets = (boxDict[s] ?? []).toList()..sort((a, b) => b.compareTo(a));
        for (int f in frets) {
          int pitch = openStrings[s]! + f;
          if (pitch < lastPitch) {
            flatNotes.add([s, f]);
            lastPitch = pitch;
          }
        }
      }
    }
    return flatNotes;
  }

  List<List<int>> apply3StepSequence(List<List<int>> baseNotes) {
    List<List<int>> result = [];
    for (int i = 0; i < baseNotes.length - 2; i++) result.addAll([baseNotes[i], baseNotes[i + 1], baseNotes[i + 2]]);
    return result;
  }

  List<List<int>> apply4StepSequence(List<List<int>> baseNotes) {
    List<List<int>> result = [];
    for (int i = 0; i < baseNotes.length - 3; i++) result.addAll([baseNotes[i], baseNotes[i + 1], baseNotes[i + 2], baseNotes[i + 3]]);
    return result;
  }

  List<List<int>> applyNoteSkipping(List<List<int>> baseNotes) {
    List<List<int>> result = [];
    for (int i = 0; i < baseNotes.length - 2; i++) result.addAll([baseNotes[i], baseNotes[i + 2]]);
    return result;
  }

  List<List<int>> buildCustomSequence(List<List<int>> baseNotes, String sequenceStr) {
    List<List<int>> result = [];
    if (baseNotes.isEmpty) return result;

    List<String> tokens = sequenceStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    for (String token in tokens) {
      int? idx = int.tryParse(token);
      if (idx != null && idx > 0 && idx <= baseNotes.length) result.add(baseNotes[idx - 1]);
    }
    return result;
  }

  // UPDATED: Now sweeps string pairs precisely in the direction dictated by startStr and endStr
  List<List<int>> buildCustomMotif(Map<int, List<int>> boxDict, String rawMotif, int startStr, int endStr) {
    if (startStr == endStr) return [];
    
    List<List<int>> pairs = [];
    if (startStr > endStr) { // Ascending sweep (e.g. 6 to 4)
      for (int i = startStr; i > endStr; i--) pairs.add([i, i - 1]);
    } else { // Descending sweep (e.g. 4 to 6)
      for (int i = startStr; i < endStr; i++) pairs.add([i + 1, i]);
    }

    List<Map<String, dynamic>> tokens = [];
    List<String> parts = rawMotif.split(',').where((p) => p.trim().isNotEmpty).toList();
    for (String p in parts) {
      p = p.trim().toUpperCase();
      if (p.length < 2) continue;
      String side = p[0];
      int? idx = int.tryParse(p.substring(1));
      if (idx != null && idx > 0 && (side == 'L' || side == 'H')) tokens.add({'side': side, 'idx': idx - 1});
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

  List<List<int>> applyIntervalBreaks(List<List<int>> sequence, int interval, int breakLen) {
    if (interval <= 0 || breakLen <= 0 || sequence.isEmpty) return sequence;
    List<List<int>> result = [];
    for (int i = 0; i < sequence.length; i++) {
      result.add(sequence[i]);
      if ((i + 1) % interval == 0) for (int b = 0; b < breakLen; b++) result.add([-1, -1]);
    }
    return result;
  }

  String renderAsciiTab(List<List<int>> noteSequence, {String rhythmStr = "16th", int measuresPerSystem = 1, int beatsPerMeasure = 4, int tempo = 120}) {
    int multiplier = {"Quarter": 1, "8th": 2, "16th": 4}[rhythmStr] ?? 4;
    int notesPerMeasure = beatsPerMeasure * multiplier;
    int notesPerSystem = notesPerMeasure * (measuresPerSystem <= 0 ? 999 : measuresPerSystem);

    Map<int, String> stringLabels = {1: 'e', 2: 'B', 3: 'G', 4: 'D', 5: 'A', 6: 'E'};
    List<String> outputLines = ["Tempo: $tempo BPM", "Time Signature: $beatsPerMeasure/4", "Rhythm: $rhythmStr notes", ""];

    for (int sysStart = 0; sysStart < noteSequence.length; sysStart += notesPerSystem) {
      int sysEnd = min(sysStart + notesPerSystem, noteSequence.length);
      List<List<int>> systemNotes = noteSequence.sublist(sysStart, sysEnd);

      Map<int, String> systemGrid = {for (int s = 1; s <= 6; s++) s: "${stringLabels[s]}|"};
      for (int idx = 0; idx < systemNotes.length; idx++) {
        var note = systemNotes[idx];
        if (idx > 0 && idx % notesPerMeasure == 0) {
          for (int s = 1; s <= 6; s++) systemGrid[s] = "${systemGrid[s]}|";
        }
        int colWidth = (note[0] != -1 && note[1] >= 10) ? 4 : 3;
        for (int s = 1; s <= 6; s++) {
          if (s == note[0]) systemGrid[s] = "${systemGrid[s]}-${note[1]}-";
          else systemGrid[s] = systemGrid[s]! + ("-" * colWidth);
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