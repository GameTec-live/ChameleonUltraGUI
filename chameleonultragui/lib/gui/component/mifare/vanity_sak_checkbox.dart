import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

class VanitySakCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const VanitySakCheckbox(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(localizations.enable_vanity_sak),
      secondary: Tooltip(
        triggerMode: TooltipTriggerMode.tap,
        // Keep the tooltip open until the user taps elsewhere.
        showDuration: const Duration(days: 1),
        message: localizations.enable_vanity_sak_tooltip,
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.info_outline),
        ),
      ),
    );
  }
}
