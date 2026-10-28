import 'package:flutter/material.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

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
    final localizations = AppLocalizations.of(context)!;
    if (!showField) {
      return ExpansionTile(
        title: Text(localizations.additional_settings),
        children: [
          TextButton(
            onPressed: () => setState(() => showField = true),
            child: Text(localizations.card_auth_add_key),
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
        labelText: localizations.card_auth_key_label,
        helperText: localizations.card_auth_key_help,
        helperMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: localizations.card_auth_key_visibility,
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => visible = !visible),
        ),
      ),
      validator: (value) {
        final key = (value ?? '').trim();
        return key.isEmpty || RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(key)
            ? null
            : localizations.card_auth_invalid_key;
      },
    );
  }
}
