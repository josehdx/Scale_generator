import 'dart:convert';
import 'dart:io';
import 'package:tab_generator/utils/midi_comparator.dart';

String resolvePath(String path) {
  if (File(path).existsSync()) return path;
  
  // Check common subdirectories if not found in root
  final candidates = [
    'test_agent/$path',
    'test/$path',
    'assets/$path',
  ];
  
  for (var candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return path;
}

void main(List<String> args) async {
  final rawGtPath = args.isNotEmpty ? args[0] : 'ground_truth.json';
  final rawOutputPath = args.length > 1 ? args[1] : 'flutter_output_fixed.json';

  final gtPath = resolvePath(rawGtPath);
  final outputPath = resolvePath(rawOutputPath);

  final gtFile = File(gtPath);
  final outputFile = File(outputPath);

  if (!await gtFile.exists() || !await outputFile.exists()) {
    print('Error: Could not find ground truth or output file.');
    print('Looked for Ground Truth at: "$gtPath"');
    print('Looked for Output File at:   "$outputPath"');
    return;
  }

  print('Loading Ground Truth: $gtPath');
  print('Loading Output File:  $outputPath');

  final List<Map<String, dynamic>> groundTruth =
      List<Map<String, dynamic>>.from(jsonDecode(await gtFile.readAsString()));

  final List<Map<String, dynamic>> parsedOutput =
      List<Map<String, dynamic>>.from(jsonDecode(await outputFile.readAsString()));

  final result = MidiComparator.evaluate(
    groundTruthRaw: groundTruth,
    parsedEventsRaw: parsedOutput,
    toleranceMs: 20.0,
  );

  print('\n=== MIDI Parser Accuracy Check ===');
  print(result);

  if (result.errorLogs.isNotEmpty) {
    print('\n--- Top 5 Discrepancies ---');
    result.errorLogs.take(5).forEach(print);
  }
}