import 'package:flutter/material.dart';
import 'studio_components.dart';

class TheorySection extends StatelessWidget {
  final bool isManualMode;
  final String manualSelectedDuration;
  final String selectedKey;
  final List<String> availableKeys;
  final String selectedScale;
  final List<String> availableScales;
  final String selectedTuning;
  final List<String> availableTunings;
  final String selectedSystem;
  final List<String> availableSystems;
  final int singleStringTarget;
  final int startString;
  final int endString;
  final int startFret;
  
  final TextEditingController customNpsController;

  final VoidCallback onCursorLeft;
  final VoidCallback onCursorRight;
  final VoidCallback onInsertRest;
  final VoidCallback onDeleteMenu;
  final ValueChanged<String?> onManualDurationChanged;
  
  final ValueChanged<String?> onKeyChanged;
  final ValueChanged<String?> onScaleChanged;
  final ValueChanged<String?> onTuningChanged;
  final ValueChanged<String?> onSystemChanged;
  final ValueChanged<String?> onSingleStringTargetChanged;
  final ValueChanged<String?> onStartStringChanged;
  final ValueChanged<String?> onEndStringChanged;
  final VoidCallback onSwapStrings;
  final ValueChanged<String> onCustomNpsChanged;
  final ValueChanged<int> onStartFretChanged;

  const TheorySection({
    super.key,
    required this.isManualMode,
    required this.manualSelectedDuration,
    required this.selectedKey,
    required this.availableKeys,
    required this.selectedScale,
    required this.availableScales,
    required this.selectedTuning,
    required this.availableTunings,
    required this.selectedSystem,
    required this.availableSystems,
    required this.singleStringTarget,
    required this.startString,
    required this.endString,
    required this.startFret,
    required this.customNpsController,
    required this.onCursorLeft,
    required this.onCursorRight,
    required this.onInsertRest,
    required this.onDeleteMenu,
    required this.onManualDurationChanged,
    required this.onKeyChanged,
    required this.onScaleChanged,
    required this.onTuningChanged,
    required this.onSystemChanged,
    required this.onSingleStringTargetChanged,
    required this.onStartStringChanged,
    required this.onEndStringChanged,
    required this.onSwapStrings,
    required this.onCustomNpsChanged,
    required this.onStartFretChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!isManualMode)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: StudioDropdown(
                  label: 'Key',
                  value: selectedKey,
                  items: availableKeys,
                  onChanged: onKeyChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 5,
                child: StudioDropdown(
                  label: 'Scale',
                  value: selectedScale,
                  items: availableScales,
                  onChanged: onScaleChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: StudioDropdown(
                  label: 'Tuning',
                  value: selectedTuning,
                  items: availableTunings,
                  onChanged: onTuningChanged,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                flex: 4,
                child: StudioDropdown(
                  label: 'Tuning (Dictates Audio Pitch)',
                  value: selectedTuning,
                  items: availableTunings,
                  onChanged: onTuningChanged,
                ),
              ),
            ],
          ),
        
        const SizedBox(height: 8),
        
        Row(
          children: [
            Expanded(
              flex: 2,
              child: StudioDropdown(
                label: 'System',
                value: selectedSystem,
                items: availableSystems,
                onChanged: onSystemChanged,
              ),
            ),
            const SizedBox(width: 8),
            if (selectedSystem == "Single String Horizontal")
              Expanded(
                flex: 2,
                child: StudioDropdown(
                  label: 'String Target',
                  value: singleStringTarget.toString(),
                  items: const ["1", "2", "3", "4", "5", "6"],
                  onChanged: onSingleStringTargetChanged,
                ),
              )
            else if (!isManualMode) ...[
              Expanded(
                child: StudioDropdown(
                  label: 'Start Str',
                  value: startString.toString(),
                  items: const ["1", "2", "3", "4", "5", "6"],
                  onChanged: onStartStringChanged,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz, color: Colors.grey),
                onPressed: onSwapStrings,
              ),
              Expanded(
                child: StudioDropdown(
                  label: 'End Str',
                  value: endString.toString(),
                  items: const ["1", "2", "3", "4", "5", "6"],
                  onChanged: onEndStringChanged,
                ),
              ),
            ],
          ],
        ),
        
        if (selectedSystem == "Custom Notes-Per-String")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: StudioTextField(
              label: "NPS Profile (e, B, G, D, A, E)",
              hintText: "e.g., 3, 4, 3, 4, 3, 3",
              controller: customNpsController,
              onChanged: onCustomNpsChanged,
            ),
          ),
          
        if (isManualMode)
          Container(
            margin: const EdgeInsets.only(top: 12.0, bottom: 4.0),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade900.withOpacity(0.3), 
              borderRadius: BorderRadius.circular(8), 
              border: Border.all(color: Colors.blueAccent.withOpacity(0.5))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: onCursorLeft),
                DropdownButton<String>(
                  value: manualSelectedDuration,
                  underline: const SizedBox(),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: "Quarter", child: Text("Quarter")),
                    DropdownMenuItem(value: "8th", child: Text("8th")),
                    DropdownMenuItem(value: "16th", child: Text("16th")),
                  ],
                  onChanged: onManualDurationChanged,
                ),
                IconButton(icon: const Icon(Icons.space_bar), tooltip: "Insert Rest", onPressed: onInsertRest),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), tooltip: "Delete", onPressed: onDeleteMenu),
                IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 18), onPressed: onCursorRight),
              ]
            )
          ),
          
        if (!isManualMode)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Text("Start Fret: $startFret"),
                Expanded(
                  child: Slider(
                    value: startFret.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: startFret.toString(),
                    onChanged: (val) => onStartFretChanged(val.toInt()),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}