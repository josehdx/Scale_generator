import 'dart:async';
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
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      ),
      value: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}

class StudioTextField extends StatelessWidget {
  final String label;
  final String hintText;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const StudioTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

class StudioNumberField extends StatefulWidget {
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
  State<StudioNumberField> createState() => _StudioNumberFieldState();
}

class _StudioNumberFieldState extends State<StudioNumberField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitValue();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    
    // Defer state update until user is completely done typing
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(StudioNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Don't override text if the user is actively typing in it
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      if (_controller.text != widget.value.toString()) {
        _controller.text = widget.value.toString();
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitValue() {
    int? parsed = int.tryParse(_controller.text);
    if (parsed != null && parsed >= 0) {
      if (parsed != widget.value) {
        widget.onChanged(parsed);
      }
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(fontSize: 11, height: 1.1),
        floatingLabelAlignment: FloatingLabelAlignment.center,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        border: const OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) => _commitValue(),
    );
  }
}

class StudioStepperField extends StatefulWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const StudioStepperField({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 999,
    required this.onChanged,
  });

  @override
  State<StudioStepperField> createState() => _StudioStepperFieldState();
}

class _StudioStepperFieldState extends State<StudioStepperField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _repeatTimer;
  Timer? _delayTimer;

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitValue();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(StudioStepperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _stopHold();
    _focusNode.removeListener(_onFocusChange);
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitValue() {
    int? parsed = int.tryParse(_controller.text);
    if (parsed != null) {
      int clamped = parsed.clamp(widget.min, widget.max);
      _controller.text = clamped.toString();
      if (clamped != widget.value) {
        widget.onChanged(clamped);
      }
    } else {
      _controller.text = widget.value.toString();
    }
  }

  void _updateValue(int delta) {
    int current = int.tryParse(_controller.text) ?? widget.value;
    int next = (current + delta).clamp(widget.min, widget.max);
    if (next != current || current != widget.value) {
      _controller.text = next.toString();
      widget.onChanged(next);
    }
  }

  void _startHold(int delta) {
    // Drop focus from text input safely
    FocusManager.instance.primaryFocus?.unfocus(); 
    
    _updateValue(delta); 
    
    _delayTimer = Timer(const Duration(milliseconds: 400), () {
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) { _stopHold(); return; }
        _updateValue(delta * 5);
      });
    });
  }

  void _stopHold() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade600),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _startHold(-1),
                onTapUp: (_) => _stopHold(),
                onTapCancel: () => _stopHold(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                  child: Icon(Icons.arrow_drop_down, size: 24),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                    border: InputBorder.none,
                  ),
                  onFieldSubmitted: (_) => _commitValue(),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _startHold(1),
                onTapUp: (_) => _stopHold(),
                onTapCancel: () => _stopHold(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                  child: Icon(Icons.arrow_drop_up, size: 24),
                ),
              ),
            ],
          ),
          // Floating Label
          Positioned(
            top: -6,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.center,
              child: Container(
                color: const Color(0xFF121212), // Matches scaffold background to clip border
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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