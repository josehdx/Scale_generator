import 'package:flutter/material.dart';

class StudioDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const StudioDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: const OutlineInputBorder(),
      ),
      value: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}

class StudioNumberField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const StudioNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, height: 1.1),
        floatingLabelAlignment: FloatingLabelAlignment.center,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        border: const OutlineInputBorder(),
      ),
      onChanged: (val) {
        int? parsed = int.tryParse(val);
        if (parsed != null && parsed >= 0) onChanged(parsed);
      },
    );
  }
}

class CollapsibleSection extends StatelessWidget {
  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  const CollapsibleSection({
    super.key,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
          onTap: onToggle,
          dense: true,
        ),
        AnimatedCrossFade(
          firstChild: Padding(padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 12.0), child: child),
          secondChild: const SizedBox.shrink(),
          crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
        const Divider(height: 1, thickness: 1, color: Colors.black26),
      ],
    );
  }
}