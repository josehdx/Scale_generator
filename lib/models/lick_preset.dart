class LickPreset {
  final String id;
  final String name;
  final String key;
  final String scale;
  final String tuning;
  final String system;
  final String fragment;
  final int startFret;
  final String pathway;
  final String direction;
  final String motifPairDirection;
  final String motifString;
  final String rhythm;
  final int tempo;
  final int measuresPerLine;
  final int breakInterval;
  final int breakLength;
  final int endRests;
  final String tabOutput;
  final DateTime createdAt;

  LickPreset({
    required this.id,
    required this.name,
    required this.key,
    required this.scale,
    required this.tuning,
    required this.system,
    required this.fragment,
    required this.startFret,
    required this.pathway,
    required this.direction,
    required this.motifPairDirection,
    required this.motifString,
    required this.rhythm,
    required this.tempo,
    required this.measuresPerLine,
    required this.breakInterval,
    required this.breakLength,
    required this.endRests,
    required this.tabOutput,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': key,
        'scale': scale,
        'tuning': tuning,
        'system': system,
        'fragment': fragment,
        'startFret': startFret,
        'pathway': pathway,
        'direction': direction,
        'motifPairDirection': motifPairDirection,
        'motifString': motifString,
        'rhythm': rhythm,
        'tempo': tempo,
        'measuresPerLine': measuresPerLine,
        'breakInterval': breakInterval,
        'breakLength': breakLength,
        'endRests': endRests,
        'tabOutput': tabOutput,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LickPreset.fromJson(Map<String, dynamic> json) => LickPreset(
        id: json['id'],
        name: json['name'],
        key: json['key'],
        scale: json['scale'],
        tuning: json['tuning'],
        system: json['system'],
        fragment: json['fragment'],
        startFret: json['startFret'],
        pathway: json['pathway'],
        direction: json['direction'],
        motifPairDirection: json['motifPairDirection'],
        motifString: json['motifString'],
        rhythm: json['rhythm'],
        tempo: json['tempo'],
        measuresPerLine: json['measuresPerLine'],
        breakInterval: json['breakInterval'],
        breakLength: json['breakLength'],
        endRests: json['endRests'],
        tabOutput: json['tabOutput'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}