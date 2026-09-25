import 'dart:math';

/// Data class representing a simplified MIDI note event for comparison.
class MidiTestEvent {
  final double timeMs;
  final String type; // 'note_on' or 'note_off'
  final int channel;
  final int pitch; // data1
  final int velocity; // data2

  MidiTestEvent({
    required this.timeMs,
    required this.type,
    required this.channel,
    required this.pitch,
    required this.velocity,
  });

  factory MidiTestEvent.fromJson(Map<String, dynamic> json) {
    return MidiTestEvent(
      timeMs: (json['time_ms'] as num).toDouble(),
      type: json['type'] as String,
      channel: json['channel'] as int,
      pitch: json['data1'] as int,
      velocity: json['data2'] as int,
    );
  }
}

/// Verification result summary.
class MidiMatchResult {
  final int totalGroundTruthNotes;
  final int matchedNotes;
  final double matchPercentage;
  final List<String> errorLogs;

  MidiMatchResult({
    required this.totalGroundTruthNotes,
    required this.matchedNotes,
    required this.matchPercentage,
    required this.errorLogs,
  });

  @override
  String toString() {
    return 'Matched Notes: $matchedNotes / $totalGroundTruthNotes (${matchPercentage.toStringAsFixed(1)}%)\n'
        'Mismatches/Dropped: ${errorLogs.length} events';
  }
}

class MidiComparator {
  /// Compares parsed MIDI events with Ground Truth using a configurable time tolerance.
  /// 
  /// - [groundTruthRaw]: JSON list of expected ground truth events.
  /// - [parsedEventsRaw]: JSON list of actual generated events.
  /// - [toleranceMs]: Allowed timestamp drift in milliseconds (default: 20.0ms).
  static MidiMatchResult evaluate({
    required List<Map<String, dynamic>> groundTruthRaw,
    required List<Map<String, dynamic>> parsedEventsRaw,
    double toleranceMs = 20.0,
  }) {
    // 1. Filter out continuous controllers (pitch_bend, vibrato, etc.)
    // Only compare note_on and note_off events.
    final gtEvents = groundTruthRaw
        .map((e) => MidiTestEvent.fromJson(e))
        .where((e) => e.type == 'note_on' || e.type == 'note_off')
        .toList();

    final parsedEvents = parsedEventsRaw
        .map((e) => MidiTestEvent.fromJson(e))
        .where((e) => e.type == 'note_on' || e.type == 'note_off')
        .toList();

    final Set<int> matchedParsedIndices = {};
    int matchedCount = 0;
    List<String> logs = [];

    // 2. Perform greedy closest-match within tolerance window
    for (int i = 0; i < gtEvents.length; i++) {
      final gt = gtEvents[i];

      int? bestCandidateIndex;
      double minDelta = double.infinity;

      for (int j = 0; j < parsedEvents.length; j++) {
        if (matchedParsedIndices.contains(j)) continue;

        final candidate = parsedEvents[j];

        // Ensure Pitch, Type, and Channel match
        if (candidate.type == gt.type &&
            candidate.pitch == gt.pitch &&
            candidate.channel == gt.channel) {
          
          double delta = (candidate.timeMs - gt.timeMs).abs();

          // Apply 20ms tolerance window and pick the closest matching timestamp
          if (delta <= toleranceMs && delta < minDelta) {
            minDelta = delta;
            bestCandidateIndex = j;
          }
        }
      }

      if (bestCandidateIndex != null) {
        matchedCount++;
        matchedParsedIndices.add(bestCandidateIndex);
      } else {
        logs.add(
          'MISSING/DRIFT [GT #$i]: ${gt.type} Pitch=${gt.pitch} Ch=${gt.channel} @ ${gt.timeMs}ms (No match within ±${toleranceMs}ms)',
        );
      }
    }

    final double percentage = gtEvents.isEmpty
        ? 100.0
        : (matchedCount / gtEvents.length) * 100.0;

    return MidiMatchResult(
      totalGroundTruthNotes: gtEvents.length,
      matchedNotes: matchedCount,
      matchPercentage: percentage,
      errorLogs: logs,
    );
  }
}