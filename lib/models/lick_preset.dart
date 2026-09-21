class LickPreset {
  final String id, name, key, scale, tuning, system, fragment, customNps, pathway, direction, motifString, rhythm, customRhythmString, customAccentString, manualTabString, tabOutput;
  final int startFret, tempo, measuresPerLine, breakInterval, breakLength, endRests, instrumentIndex;
  final DateTime createdAt;

  LickPreset({
    required this.id, required this.name, required this.key, required this.scale, required this.tuning,
    required this.system, required this.fragment, required this.customNps, required this.startFret, required this.pathway,
    required this.direction, required this.motifString, required this.rhythm, required this.customRhythmString, 
    required this.customAccentString, required this.manualTabString,
    required this.tempo, required this.measuresPerLine, required this.breakInterval,
    required this.breakLength, required this.endRests, required this.tabOutput, required this.instrumentIndex, required this.createdAt
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'key': key, 'scale': scale, 'tuning': tuning, 'system': system,
    'fragment': fragment, 'customNps': customNps, 'startFret': startFret, 'pathway': pathway, 'direction': direction,
    'motifString': motifString, 'rhythm': rhythm, 'customRhythmString': customRhythmString,
    'customAccentString': customAccentString, 'manualTabString': manualTabString,
    'tempo': tempo, 'measuresPerLine': measuresPerLine, 'breakInterval': breakInterval,
    'breakLength': breakLength, 'endRests': endRests, 'tabOutput': tabOutput, 'instrumentIndex': instrumentIndex, 'createdAt': createdAt.toIso8601String()
  };

  factory LickPreset.fromJson(Map<String, dynamic> json) => LickPreset(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    key: json['key'] ?? 'C',
    scale: json['scale'] ?? 'Minor Pentatonic',
    tuning: json['tuning'] ?? 'Standard E',
    system: json['system'] ?? 'Box Position / CAGED',
    fragment: json['fragment'] ?? 'Full 6 Strings',
    customNps: json['customNps'] ?? '3,3,3,3,3,3',
    startFret: json['startFret'] ?? 5,
    pathway: json['pathway'] ?? 'Straight Linear',
    direction: json['direction'] ?? 'Ascend -> Descend',
    motifString: json['motifString'] ?? '',
    rhythm: json['rhythm'] ?? '16th',
    customRhythmString: json['customRhythmString'] ?? '16,16,8',
    customAccentString: json['customAccentString'] ?? '1,0,0,0',
    manualTabString: json['manualTabString'] ?? '6:5, 6:8, 5:5, 5:7',
    tempo: json['tempo'] ?? 120,
    measuresPerLine: json['measuresPerLine'] ?? 1,
    breakInterval: json['breakInterval'] ?? 0,
    breakLength: json['breakLength'] ?? 4,
    endRests: json['endRests'] ?? 0,
    tabOutput: json['tabOutput'] ?? '',
    instrumentIndex: json['instrumentIndex'] ?? 27,
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
  );
}