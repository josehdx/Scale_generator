import 'dart:convert';
import 'dart:io';

class MidiEvent {
  final double timeMs;
  final String type;
  final int channel;
  final int pitch;
  final int velocity;

  MidiEvent.fromJson(Map<String, dynamic> json)
      : timeMs = (json['time_ms'] as num).toDouble(),
        type = json['type'] as String,
        channel = json['channel'] as int,
        pitch = json['data1'] as int,
        velocity = json['data2'] as int;
}

void main(List<String> args) {
  if (args.length < 2) {
    print('Usage: dart run bin/audit_midi.dart <ground_truth.json> <flutter_output.json>');
    return;
  }

  final gtFile = File(args[0]);
  final flFile = File(args[1]);

  if (!gtFile.existsSync() || !flFile.existsSync()) {
    print('Error: One or both files not found.');
    return;
  }

  final gtRaw = jsonDecode(gtFile.readAsStringSync()) as List<dynamic>;
  final flRaw = jsonDecode(flFile.readAsStringSync()) as List<dynamic>;

  final gtEvents = gtRaw.map((e) => MidiEvent.fromJson(e)).toList();
  final flEvents = flRaw.map((e) => MidiEvent.fromJson(e)).toList();

  print('\n=== DEEP AUDIT LOG ===');

  _auditDuplicateTies(flEvents);
  _auditTuningInversions(gtEvents, flEvents);
  _auditDroppedNotes(gtEvents, flEvents);
}

void _auditDuplicateTies(List<MidiEvent> flEvents) {
  print('\n--- 1. DUPLICATE NOTES (TIE FAILURES) ---');
  print('Hunting for note_on events fired while the same pitch is already active...');
  
  Map<String, double> activeNotes = {};
  int duplicateCount = 0;

  for (var ev in flEvents) {
    String key = '${ev.channel}_${ev.pitch}';
    
    if (ev.type == 'note_on' && ev.velocity > 0) {
      if (activeNotes.containsKey(key)) {
        duplicateCount++;
        if (duplicateCount <= 10) {
          print(' DUPLICATE TIE: Ch=${ev.channel} Pitch=${ev.pitch} fired at ${ev.timeMs}ms, but was already turned ON at ${activeNotes[key]}ms without a note_off!');
        }
      }
      activeNotes[key] = ev.timeMs;
    } else if (ev.type == 'note_off' || (ev.type == 'note_on' && ev.velocity == 0)) {
      activeNotes.remove(key);
    }
  }
  
  if (duplicateCount > 10) print(' ...and ${duplicateCount - 10} more duplicate tie errors.');
  if (duplicateCount == 0) print(' -> No duplicate tie errors found.');
}

void _auditTuningInversions(List<MidiEvent> gtEvents, List<MidiEvent> flEvents) {
  print('\n--- 2. PITCH MISMATCHES (TUNING INVERSIONS) ---');
  print('Hunting for notes that fired at the EXACT same time, but on the wrong pitch...');

  int mismatchCount = 0;
  
  for (var gt in gtEvents.where((e) => e.type == 'note_on' && e.velocity > 0)) {
    // Find all flutter events within 5ms of this GT event
    var simultaneousFl = flEvents.where((fl) => 
      fl.type == 'note_on' && 
      fl.velocity > 0 && 
      (fl.timeMs - gt.timeMs).abs() <= 5.0
    ).toList();

    if (simultaneousFl.isNotEmpty) {
      // If none of the simultaneous notes match the GT pitch, we have a tuning issue
      bool pitchFound = simultaneousFl.any((fl) => fl.pitch == gt.pitch);
      
      if (!pitchFound) {
        mismatchCount++;
        if (mismatchCount <= 10) {
          print(' TUNING MISMATCH @ ${gt.timeMs}ms: Ground Truth expected Pitch=${gt.pitch}, but Flutter output played Pitch(es)=${simultaneousFl.map((e)=>e.pitch).toList()}');
        }
      }
    }
  }

  if (mismatchCount > 10) print(' ...and ${mismatchCount - 10} more tuning pitch mismatches.');
  if (mismatchCount == 0) print(' -> No tuning mismatches found.');
}

void _auditDroppedNotes(List<MidiEvent> gtEvents, List<MidiEvent> flEvents) {
  print('\n--- 3. COMPLETELY DROPPED NOTES ---');
  print('Hunting for Ground Truth notes where Flutter output has NO events at that timestamp...');

  int droppedCount = 0;

  for (var gt in gtEvents.where((e) => e.type == 'note_on' && e.velocity > 0)) {
    // Check if Flutter produced ANY note_on within a wide 50ms window
    bool temporalMatchExists = flEvents.any((fl) => 
      fl.type == 'note_on' && 
      fl.velocity > 0 && 
      (fl.timeMs - gt.timeMs).abs() <= 50.0
    );

    if (!temporalMatchExists) {
      droppedCount++;
      if (droppedCount <= 10) {
        print(' DEAD SILENCE @ ${gt.timeMs}ms: GT expected Pitch=${gt.pitch} Ch=${gt.channel}, but Flutter output is completely silent in this window.');
      }
    }
  }

  if (droppedCount > 10) print(' ...and ${droppedCount - 10} more completely dropped notes.');
  if (droppedCount == 0) print(' -> No completely dropped notes found.');
}