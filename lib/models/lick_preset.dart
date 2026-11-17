class LickPreset {
  final String id, name, key, scale, tuning, system, fragment, customNps, pathway, direction, motifString, rhythm, customRhythmString, customAccentString, manualTabString, timeSignature, tabOutput;
  final int startFret, tempo, measuresPerLine, breakInterval, breakLength, endRests, instrumentIndex, patternMultiplier;
  final DateTime createdAt;

  LickPreset({
    required this.id, required this.name, required this.key, required this.scale, required this.tuning,
    required this.system, required this.fragment, required this.customNps, required this.startFret, required this.pathway,
    required this.direction, required this.motifString, required this.rhythm, required this.customRhythmString,
    required this.customAccentString, required this.manualTabString, required this.timeSignature,
    required this.tempo, required this.measuresPerLine, required this.breakInterval,
    required this.breakLength, required this.endRests, required this.tabOutput, required this.instrumentIndex,
    required this.patternMultiplier, required this.createdAt
  });

  LickPreset copyWith({
    String? id, String? name, String? key, String? scale, String? tuning, String? system, String? fragment,
    String? customNps, int? startFret, String? pathway, String? direction, String? motifString, String? rhythm,
    String? customRhythmString, String? customAccentString, String? manualTabString, String? timeSignature,
    int? tempo, int? measuresPerLine, int? breakInterval, int? breakLength, int? endRests, String? tabOutput,
    int? instrumentIndex, int? patternMultiplier, DateTime? createdAt,
  }) => LickPreset(
    id: id ?? this.id, name: name ?? this.name, key: key ?? this.key, scale: scale ?? this.scale,
    tuning: tuning ?? this.tuning, system: system ?? this.system, fragment: fragment ?? this.fragment,
    customNps: customNps ?? this.customNps, startFret: startFret ?? this.startFret, pathway: pathway ?? this.pathway,
    direction: direction ?? this.direction, motifString: motifString ?? this.motifString, rhythm: rhythm ?? this.rhythm,
    customRhythmString: customRhythmString ?? this.customRhythmString,
    customAccentString: customAccentString ?? this.customAccentString,
    manualTabString: manualTabString ?? this.manualTabString, timeSignature: timeSignature ?? this.timeSignature,
    tempo: tempo ?? this.tempo, measuresPerLine: measuresPerLine ?? this.measuresPerLine,
    breakInterval: breakInterval ?? this.breakInterval, breakLength: breakLength ?? this.breakLength,
    endRests: endRests ?? this.endRests, tabOutput: tabOutput ?? this.tabOutput,
    instrumentIndex: instrumentIndex ?? this.instrumentIndex,
    patternMultiplier: patternMultiplier ?? this.patternMultiplier, createdAt: createdAt ?? this.createdAt,
  );

  static const int minTempo = 40;
  static const int maxTempo = 300;

  /// Returns a copy of this preset with an updated [tempo].
  LickPreset updateTempo(int newTempo) => copyWith(tempo: newTempo);

  /// Returns a copy of this preset with an updated [tempo].
  LickPreset copyWithTempo(int newTempo) => copyWith(tempo: newTempo);

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'key': key, 'scale': scale, 'tuning': tuning, 'system': system,
    'fragment': fragment, 'customNps': customNps, 'startFret': startFret, 'pathway': pathway, 'direction': direction,
    'motifString': motifString, 'rhythm': rhythm, 'customRhythmString': customRhythmString,
    'customAccentString': customAccentString, 'manualTabString': manualTabString, 'timeSignature': timeSignature,
    'tempo': tempo, 'measuresPerLine': measuresPerLine, 'breakInterval': breakInterval,
    'breakLength': breakLength, 'endRests': endRests, 'tabOutput': tabOutput, 'instrumentIndex': instrumentIndex,
    'patternMultiplier': patternMultiplier, 'createdAt': createdAt.toIso8601String()
  };

  // Every field is read defensively: a value of the wrong type (hand-edited or
  // imported JSON) falls back to the default instead of throwing a TypeError.
  static String _s(Map<String, dynamic> j, String k, String d) {
    final v = j[k];
    return v is String ? v : d;
  }

  static int _i(Map<String, dynamic> j, String k, int d) {
    final v = j[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? d;
    return d;
  }

  factory LickPreset.fromJson(Map<String, dynamic> json) {
    final rawRhythm = _s(json, 'rhythm', 'Straight 16ths');
    return LickPreset(
      id: _s(json, 'id', ''),
      name: _s(json, 'name', ''),
      key: _s(json, 'key', 'C'),
      scale: _s(json, 'scale', 'Minor Pentatonic'),
      tuning: _s(json, 'tuning', 'Standard E'),
      system: _s(json, 'system', 'Box Position / CAGED'),
      fragment: _s(json, 'fragment', 'Full 6 Strings'),
      customNps: _s(json, 'customNps', '3,3,3,3,3,3'),
      startFret: _i(json, 'startFret', 5),
      pathway: _s(json, 'pathway', 'Straight Linear'),
      direction: _s(json, 'direction', 'Ascend -> Descend'),
      motifString: _s(json, 'motifString', ''),
      rhythm: rawRhythm == '16th' ? 'Straight 16ths' : rawRhythm,
      customRhythmString: _s(json, 'customRhythmString', '16,16,8'),
      customAccentString: _s(json, 'customAccentString', '1,0,0,0'),
      manualTabString: _s(json, 'manualTabString', '6:5, 6:8, 5:5, 5:7'),
      timeSignature: _s(json, 'timeSignature', 'Auto'),
      tempo: _i(json, 'tempo', 120),
      measuresPerLine: _i(json, 'measuresPerLine', 1),
      breakInterval: _i(json, 'breakInterval', 0),
      breakLength: _i(json, 'breakLength', 4),
      endRests: _i(json, 'endRests', 0),
      tabOutput: _s(json, 'tabOutput', ''),
      instrumentIndex: _i(json, 'instrumentIndex', 27),
      patternMultiplier: _i(json, 'patternMultiplier', 1),
      createdAt: DateTime.tryParse(_s(json, 'createdAt', '')) ?? DateTime.now(),
    );
  }
}
