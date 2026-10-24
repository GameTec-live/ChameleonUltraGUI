import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:flutter/material.dart';

class FirmwareRepositoryInput extends StatefulWidget {
  final String initialValue;
  final void Function(String) onSave;

  const FirmwareRepositoryInput(
      {super.key, required this.initialValue, required this.onSave});

  @override
  State<FirmwareRepositoryInput> createState() =>
      _FirmwareRepositoryInputState();
}

class _FirmwareRepositoryInputState extends State<FirmwareRepositoryInput> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController controller =
      TextEditingController(text: widget.initialValue);
  late String saved = widget.initialValue;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void save(String value) {
    // Pasted values often carry surrounding whitespace
    controller.text = value.trim();
    if (formKey.currentState!.validate()) {
      widget.onSave(controller.text);
      setState(() => saved = controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        // Buttons sit below the field so it keeps its width on small phones
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
                controller: controller,
                validator: (value) =>
                    validateRepository(value?.trim(), localizations),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: defaultFirmwareRepository,
                )),
            const SizedBox(height: 5),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: saved == defaultFirmwareRepository &&
                          controller.text.trim() == defaultFirmwareRepository
                      ? null
                      : () => save(defaultFirmwareRepository),
                  child: Text(localizations.def),
                ),
                // Disabled once saved, which doubles as confirmation
                ElevatedButton(
                  onPressed: controller.text.trim() == saved
                      ? null
                      : () => save(controller.text),
                  child: Text(localizations.save),
                ),
              ],
            ),
          ],
        ));
  }
}
