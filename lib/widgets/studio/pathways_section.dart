import 'package:flutter/material.dart';
import '../../models/motif_token.dart';
import 'studio_components.dart';

class PathwaysSection extends StatelessWidget {
  final String selectedPathway;
  final List<String> availablePathways;
  final String selectedDirection;
  final List<String> availableDirections;
  final String selectedSystem;
  final List<MotifToken> motifTokens;
  final TextEditingController customSequenceController;

  final ValueChanged<String?> onPathwayChanged;
  final ValueChanged<String?> onDirectionChanged;
  final ValueChanged<String> onMotifAdded;
  final Function(int) onMotifRemoved;
  final Function(int, int) onMotifReordered;
  final VoidCallback onClearMotifs;
  final ValueChanged<String> onCustomSequenceChanged;

  const PathwaysSection({
    super.key,
    required this.selectedPathway,
    required this.availablePathways,
    required this.selectedDirection,
    required this.availableDirections,
    required this.selectedSystem,
    required this.motifTokens,
    required this.customSequenceController,
    required this.onPathwayChanged,
    required this.onDirectionChanged,
    required this.onMotifAdded,
    required this.onMotifRemoved,
    required this.onMotifReordered,
    required this.onClearMotifs,
    required this.onCustomSequenceChanged,
  });

  Widget _buildMotifChipBuilder() {
    int maxNotes = 4;
    if (selectedSystem == "3-Note-Per-String (3NPS)") maxNotes = 6;
    else if (selectedSystem == "Box Position / CAGED") maxNotes = 4;
    else if (selectedSystem == "Custom Notes-Per-String") maxNotes = 8;
    
    List<String> availableNotes = [];
    for(int i = 1; i <= maxNotes; i++) availableNotes.add("L$i");
    for(int i = 1; i <= maxNotes; i++) availableNotes.add("H$i");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 12.0, bottom: 4.0),
          child: Text("Motif Timeline (Drag to reorder):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: motifTokens.isEmpty
              ? const Center(child: Text("Sequence empty. Add notes from below.", style: TextStyle(color: Colors.grey, fontSize: 12)))
              : ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  itemCount: motifTokens.length,
                  itemBuilder: (context, index) {
                    final token = motifTokens[index];
                    bool isLower = token.value.startsWith('L');
                    return Padding(
                      key: ValueKey(token.id),
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InputChip(
                        label: Text(token.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                        backgroundColor: isLower ? Colors.blue.shade900 : Colors.teal.shade900,
                        deleteIcon: const Icon(Icons.cancel, size: 16, color: Colors.white70),
                        onDeleted: () => onMotifRemoved(index),
                      ),
                    );
                  },
                  onReorder: onMotifReordered,
                ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12.0, bottom: 4.0),
          child: Text("Available Notes Bank (Tap to add):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: availableNotes.map((note) {
            bool isLower = note.startsWith('L');
            return ActionChip(
              label: Text(note),
              backgroundColor: Colors.grey.shade900,
              side: BorderSide(color: isLower ? Colors.blue.shade700 : Colors.teal.shade700),
              onPressed: () => onMotifAdded(note),
            );
          }).toList(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onClearMotifs,
            icon: const Icon(Icons.delete_sweep, size: 16, color: Colors.redAccent),
            label: const Text("Clear Sequence", style: TextStyle(color: Colors.redAccent)),
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 2, child: StudioDropdown(label: 'Pathway', value: selectedPathway, items: availablePathways, onChanged: onPathwayChanged)),
            const SizedBox(width: 8),
            Expanded(
              flex: 2, 
              child: selectedPathway == "Custom Motif Builder"
                  ? const SizedBox.shrink()
                  : StudioDropdown(label: 'Loop Direction', value: selectedDirection, items: availableDirections, onChanged: onDirectionChanged)
            ),
          ],
        ),
        if (selectedPathway == "Custom Motif Builder")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: _buildMotifChipBuilder(),
          )
        else if (selectedPathway == "Custom Sequence (Indices)")
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextField(
              controller: customSequenceController,
              decoration: const InputDecoration(labelText: "Note Sequence (1-based index)", hintText: "e.g., 1, 2, 3, 2, 3, 4", border: OutlineInputBorder(), isDense: true),
              onChanged: onCustomSequenceChanged,
            ),
          ),
      ],
    );
  }
}