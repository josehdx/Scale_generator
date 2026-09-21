import 'package:flutter/material.dart';
import 'studio_components.dart';

class FormattingSection extends StatelessWidget {
  final String selectedRhythmPattern;
  final List<String> availableRhythmPatterns;
  final int tempo;
  final int measuresPerLine;
  final String currentNps;
  final TextEditingController customRhythmController;
  final TextEditingController customAccentController;
  final String selectedInstrumentKey;
  final List<String> availableInstruments;
  final int breakInterval;
  final int breakLength;
  final int endRests;

  final ValueChanged<String?> onRhythmChanged;
  final ValueChanged<int> onTempoChanged;
  final ValueChanged<int> onMeasuresChanged;
  final ValueChanged<String> onCustomRhythmChanged;
  final ValueChanged<String> onCustomAccentChanged;
  final ValueChanged<String?> onInstrumentChanged;
  final ValueChanged<int> onBreakIntervalChanged;
  final ValueChanged<int> onBreakLengthChanged;
  final ValueChanged<int> onEndRestsChanged;

  const FormattingSection({
    super.key,
    required this.selectedRhythmPattern,
    required this.availableRhythmPatterns,
    required this.tempo,
    required this.measuresPerLine,
    required this.currentNps,
    required this.customRhythmController,
    required this.customAccentController,
    required this.selectedInstrumentKey,
    required this.availableInstruments,
    required this.breakInterval,
    required this.breakLength,
    required this.endRests,
    required this.onRhythmChanged,
    required this.onTempoChanged,
    required this.onMeasuresChanged,
    required this.onCustomRhythmChanged,
    required this.onCustomAccentChanged,
    required this.onInstrumentChanged,
    required this.onBreakIntervalChanged,
    required this.onBreakLengthChanged,
    required this.onEndRestsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: StudioDropdown(label: 'Rhythm Pattern', value: selectedRhythmPattern, items: availableRhythmPatterns, onChanged: onRhythmChanged),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: StudioNumberField(label: 'Tempo BPM', value: tempo, onChanged: onTempoChanged),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StudioNumberField(label: 'Lines', value: measuresPerLine, onChanged: onMeasuresChanged),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Peak Physical Speed:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(
                  "$currentNps NPS", 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)
                ),
              ],
            ),
          ),
        ),
        if (selectedRhythmPattern == "Custom Pattern")
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: StudioTextField(
              label: "Custom Rhythm Pattern",
              hintText: "e.g. 16,16,8,4",
              controller: customRhythmController,
              onChanged: onCustomRhythmChanged,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: StudioTextField(
            label: "Accent Pattern (1=Max Velocity, 0=Normal)",
            hintText: "e.g., 1,0,0,0",
            controller: customAccentController,
            onChanged: onCustomAccentChanged,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: StudioDropdown(label: 'Guitar Sound', value: selectedInstrumentKey, items: availableInstruments, onChanged: onInstrumentChanged),
            ),
            const SizedBox(width: 8),
            Expanded(child: StudioNumberField(label: 'Interval', value: breakInterval, onChanged: onBreakIntervalChanged)),
            const SizedBox(width: 8),
            Expanded(child: StudioNumberField(label: 'Length', value: breakLength, onChanged: onBreakLengthChanged)),
            const SizedBox(width: 8),
            Expanded(child: StudioNumberField(label: 'Rests', value: endRests, onChanged: onEndRestsChanged)),
          ],
        ),
      ],
    );
  }
}