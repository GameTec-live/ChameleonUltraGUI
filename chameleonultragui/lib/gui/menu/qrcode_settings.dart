import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class QRCodeSettings extends StatefulWidget {
  const QRCodeSettings({Key? key})
      : super(
          key: key,
        );

  @override
  QRCodeSettingsState createState() => QRCodeSettingsState();
}

class QRCodeSettingsState extends State<QRCodeSettings> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  TextEditingController splitSize = TextEditingController(text: "2048");
  TextEditingController errorCorrection = TextEditingController(text: "0");
  int sliderSplitSize = 2048;
  int sliderErrorCorrection = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.qr_code_settings),
      content: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: () {
          if (formKey.currentState!.validate()) {
            setState(() {
              sliderSplitSize = int.parse(splitSize.text);
              sliderErrorCorrection = int.parse(errorCorrection.text);
            });
          }
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              Slider(
                value: sliderSplitSize.toDouble(),
                onChanged: (double value) {
                  if (sliderErrorCorrection.toInt() == 2 && value > 1200) {
                    sliderErrorCorrection = 3;
                  } else if (sliderErrorCorrection.toInt() == 3 &&
                      value > 1600) {
                    sliderErrorCorrection = 0;
                  }

                  setState(() {
                    sliderErrorCorrection = sliderErrorCorrection;
                    errorCorrection.text = sliderErrorCorrection.toString();
                    sliderSplitSize = value.toInt();
                    splitSize.text = value.toInt().toString();
                  });
                },
                min: 1,
                max: 2048,
              ),
              SizedBox(
                width: MediaQuery.of(context).size.width,
                child: TextFormField(
                  controller: splitSize,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.split_size,
                    hintText: "2048",
                    suffix: Tooltip(
                      message: AppLocalizations.of(context)!.split_size_tooltip,
                      child: const Icon(Icons.info_outline),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppLocalizations.of(context)!
                          .please_enter_something("Split Size");
                    }
                    if (int.tryParse(value) == null) {
                      return AppLocalizations.of(context)!
                          .please_enter_a_valid_number;
                    }
                    if (int.tryParse(value)! < 1) {
                      return AppLocalizations.of(context)!
                          .please_enter_a_number_greater_than("0");
                    }
                    if (int.tryParse(value)! > 2048) {
                      return AppLocalizations.of(context)!
                          .please_enter_a_valid_number;
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 50),
              Slider(
                value: sliderErrorCorrection.toDouble(),
                onChanged: (double value) {
                  if (value.toInt() == 0 && sliderSplitSize > 2048) {
                    sliderSplitSize = 2048;
                  } else if (value.toInt() == 1 && sliderSplitSize > 2048) {
                    sliderSplitSize = 2048;
                  } else if (value.toInt() == 2 && sliderSplitSize > 1200) {
                    sliderSplitSize = 1200;
                  } else if (value.toInt() == 3 && sliderSplitSize > 1600) {
                    sliderSplitSize = 1600;
                  }
                  setState(() {
                    sliderSplitSize = sliderSplitSize;
                    splitSize.text = sliderSplitSize.toString();
                    sliderErrorCorrection = value.toInt();
                    errorCorrection.text = value.toInt().toString();
                  });
                },
                min: 0,
                max: 3,
              ),
              SizedBox(
                width: MediaQuery.of(context).size.width,
                child: TextFormField(
                  controller: errorCorrection,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.error_correction,
                    hintText: "0",
                    suffix: Tooltip(
                      message: AppLocalizations.of(context)!
                          .error_correction_tooltip,
                      child: const Icon(Icons.info_outline),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppLocalizations.of(context)!
                          .please_enter_something("Error Correction");
                    }
                    if (int.tryParse(value) == null) {
                      return AppLocalizations.of(context)!
                          .please_enter_a_valid_number;
                    }
                    if (int.tryParse(value)! < 0 || int.tryParse(value)! > 3) {
                      return AppLocalizations.of(context)!
                          .please_enter_a_number_between("0", "3");
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 50),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(AppLocalizations.of(context)!.test_qr_code)),
              const SizedBox(height: 10),
              SizedBox(
                width: MediaQuery.of(context).size.width >
                        MediaQuery.of(context).size.height
                    ? MediaQuery.of(context).size.height * 0.8
                    : MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.width >
                        MediaQuery.of(context).size.height
                    ? MediaQuery.of(context).size.height * 0.8
                    : MediaQuery.of(context).size.width * 0.8,
                child: QrImageView(
                  // Generate dummy data on the fly depending on the splitsize
                  data: List.filled(sliderSplitSize, "a").join(""),
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(20.0),
                  errorCorrectionLevel: sliderErrorCorrection,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              int splitSizeInt = int.parse(splitSize.text);
              int errorCorrectionInt = int.parse(errorCorrection.text);
              // Level 0: max splitsize: 2048 (default)
              // Level 1: max splitsize: 2048
              // Level 2: max splitsize: 1200
              // Level 3: max splitsize: 1600
              // L = 1;
              // M = 0;
              // Q = 3;
              // H = 2;
              if (errorCorrectionInt == 0 && splitSizeInt > 2048) {
                splitSizeInt = 2048;
              } else if (errorCorrectionInt == 1 && splitSizeInt > 2048) {
                splitSizeInt = 2048;
              } else if (errorCorrectionInt == 2 && splitSizeInt > 1200) {
                splitSizeInt = 1200;
              } else if (errorCorrectionInt == 3 && splitSizeInt > 1600) {
                splitSizeInt = 1600;
              }

              Navigator.pop(context, {
                "splitSize": splitSizeInt,
                "errorCorrection": errorCorrectionInt,
              });
            }
          },
          child: Text(AppLocalizations.of(context)!.ok),
        ),
      ],
    );
  }
}
