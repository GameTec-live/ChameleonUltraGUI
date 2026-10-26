import 'package:flutter/material.dart';

class CardAuthKeyField extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool initiallyVisible;

  const CardAuthKeyField({
    super.key,
    this.controller,
    this.onChanged,
    this.initiallyVisible = true,
  });

  @override
  State<CardAuthKeyField> createState() => _CardAuthKeyFieldState();
}

class _CardAuthKeyFieldState extends State<CardAuthKeyField> {
  bool visible = false;
  late bool showField;

  @override
  void initState() {
    super.initState();
    showField =
        widget.initiallyVisible ||
        (widget.controller?.text.isNotEmpty ?? false);
  }

  @override
  void didUpdateWidget(CardAuthKeyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyVisible ||
        (widget.controller?.text.isNotEmpty ?? false)) {
      showField = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!showField) {
      return ExpansionTile(
        title: const Text('Additional settings'),
        children: [
          TextButton(
            onPressed: () => setState(() => showField = true),
            child: const Text('Add CardAuth key'),
          ),
        ],
      );
    }
    return TextFormField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: 'CardAuth key (0x9004)',
        helperText: 'Optional AES-128 key: 32 hexadecimal characters.',
        helperMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: 'Show/hide CardAuth key',
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => visible = !visible),
        ),
      ),
      validator: (value) {
        final key = (value ?? '').trim();
        return key.isEmpty || RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(key)
            ? null
            : 'Enter exactly 32 hex characters';
      },
    );
  }
}
