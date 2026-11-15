import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Decimal identity fields shared by ioProx creation and editing.
class IoProxFields extends StatelessWidget {
  final TextEditingController versionController;
  final TextEditingController facilityCodeController;
  final TextEditingController cardNumberController;

  const IoProxFields({
    super.key,
    required this.versionController,
    required this.facilityCodeController,
    required this.cardNumberController,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Column(children: [
      for (final field in [
        (versionController, localizations.version, 255),
        (facilityCodeController, localizations.facility_code, 255),
        (cardNumberController, localizations.card_number, 65535),
      ]) ...[
        const SizedBox(height: 20),
        TextFormField(
          controller: field.$1,
          decoration: InputDecoration(labelText: field.$2),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (value) =>
              validateIntRange(value, localizations, min: 0, max: field.$3),
        ),
      ],
    ]);
  }
}
