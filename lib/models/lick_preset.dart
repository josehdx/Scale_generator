class LickPreset {
  final String id, name, key, scale, tuning, system, fragment, pathway, direction, motifPairDirection, motifString, rhythm, tabOutput;
  final int startFret, tempo, measuresPerLine, breakInterval, breakLength, endRests;
  final DateTime createdAt;

  LickPreset({
    required this.id, required this.name, required this.key, required this.scale, required this.tuning,
    required this.system, required this.fragment, required this.startFret, required this.pathway,
    required this.direction, required this.motifPairDirection, required this.motifString,
    required this.rhythm, required this.tempo, required this.measuresPerLine, required this.breakInterval,
    required this.breakLength, required this.endRests, required this.tabOutput, required this.createdAt
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'key': key, 'scale': scale, 'tuning': tuning, 'system': system,
    'fragment': fragment, 'startFret': startFret, 'pathway': pathway, 'direction': direction,
    'motifPairDirection': motifPairDirection, 'motifString': motifString, 'rhythm': rhythm,
    'tempo': tempo, 'measuresPerLine': measuresPerLine, 'breakInterval': breakInterval,
    'breakLength': breakLength, 'endRests': endRests, 'tabOutput': tabOutput, 'createdAt': createdAt.toIso8601String()
  };
}