import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LongPressThresholdInput extends StatefulWidget {
  // Firmware raises anything below 200 ms to 200 ms and stores it as u16
  static const int min = 200;
  static const int max = 65535;

  // Slider snaps to 50 ms steps with the 1000 ms default in the middle,
  // values outside of it can still be typed in
  static const int sliderMax = 1800;
  static const int sliderStep = 50;

  final int initialValue;
  final Future<void> Function(int) onSave;

  const LongPressThresholdInput(
      {super.key, required this.initialValue, required this.onSave});

  @override
  State<LongPressThresholdInput> createState() =>
      _LongPressThresholdInputState();
}

class _LongPressThresholdInputState extends State<LongPressThresholdInput> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController controller =
      TextEditingController(text: widget.initialValue.toString());

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    int sliderValue = (int.tryParse(controller.text) ?? widget.initialValue)
        .clamp(LongPressThresholdInput.min, LongPressThresholdInput.sliderMax);

    return Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          children: [
            Slider(
              value: sliderValue.toDouble(),
              min: LongPressThresholdInput.min.toDouble(),
              max: LongPressThresholdInput.sliderMax.toDouble(),
              divisions: (LongPressThresholdInput.sliderMax -
                      LongPressThresholdInput.min) ~/
                  LongPressThresholdInput.sliderStep,
              onChanged: (double value) {
                setState(() {
                  controller.text = value.round().toString();
                });
              },
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      validator: (value) => validateIntRange(
                            value,
                            localizations,
                            min: LongPressThresholdInput.min,
                            max: LongPressThresholdInput.max,
                          ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        // Always visible, slider covers only part of the range
                        helperText:
                            "${LongPressThresholdInput.min}-${LongPressThresholdInput.max}",
                      )),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      await widget.onSave(int.parse(controller.text));
                    }
                  },
                  child: Text(localizations.save),
                ),
              ],
            ),
          ],
        ));
  }
}
