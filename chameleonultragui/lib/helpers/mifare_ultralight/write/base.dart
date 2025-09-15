import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/services.dart';

class BaseMifareUltralightWriteHelper extends AbstractWriteHelper {
  HFCardInfo? hfInfo;
  List<int> failedBlocks = [];

  @override
  bool get autoDetect => false;

  @override
  String get name => "gen2";

  static String get staticName => "gen2";
  TextEditingController keyController = TextEditingController();
  String? key;

  BaseMifareUltralightWriteHelper(super.communicator);

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      BaseMifareUltralightWriteHelper(communicator),
    ];
  }

  @override
  List<AbstractWriteHelper> getAvailableMethodsByPriority() {
    return [BaseMifareUltralightWriteHelper(communicator)];
  }

  @override
  Widget getWriteWidget(BuildContext context, setState) {
    var localizations = AppLocalizations.of(context)!;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Row(children: [
      Expanded(
          child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                children: [
                  TextFormField(
                    controller: keyController,
                    decoration: InputDecoration(
                        labelText: localizations.key,
                        hintMaxLines: 4,
                        hintText: localizations.enter_something(
                            localizations.ultralight_key_prompt)),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Fa-f: ]'))
                    ],
                    validator: (String? value) {
                      if (value!.isNotEmpty && !isValidHexString(value)) {
                        return localizations.must_be_valid_hex;
                      }

                      if (value.length != 8) {
                        return localizations.must_be(4, localizations.key);
                      }

                      return null;
                    },
                  )
                ],
              ))),
      TextButton(
        onPressed: () => {
          setState(() {
            key = keyController.text;
          })
        },
        child: Text(localizations.next),
      ),
      TextButton(
        onPressed: () => {
          setState(() {
            key = "";
          })
        },
        child: Text(localizations.no_key),
      )
    ]);
  }

  @override
  Future<bool> isCompatible(CardSave card) async {
    return true;
  }

  @override
  Future<bool> isMagic(data) async {
    return false;
  }

  @override
  bool isReady() {
    return key != null;
  }

  @override
  bool writeWidgetSupported() {
    return true;
  }

  @override
  Future<void> reset() async {
    failedBlocks = [];
    key = null;
  }

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    int totalBlocks = card.data.length;

    if (!await communicator.isReaderDeviceMode()) {
      await communicator.setReaderDeviceMode(true);
    }

    if (await communicator.scan14443aTag() == null) {
      return false;
    }

    if (key!.isNotEmpty) {
      Uint8List pack = await communicator.send14ARaw(
          Uint8List.fromList([0x1B, ...hexToBytes(key!)]),
          keepRfField: true);
      if (pack.length < 2) {
        return false;
      }
    }

    for (var block = 0; block < totalBlocks; block++) {
      Uint8List write = await communicator.send14ARaw(
          Uint8List.fromList([0xA2, block, ...card.data[block]]),
          keepRfField: true,
          checkResponseCrc: false,
          autoSelect: block == 0 || block == 3);
      if (write.isEmpty || write[0] != 0x0A || block == 2) {
        await communicator.send14ARaw(Uint8List(1)); // reset

        if (key!.isNotEmpty) {
          await communicator.send14ARaw(
              Uint8List.fromList([0x1B, ...hexToBytes(key!)]),
              keepRfField: true);
        }

        if (block > 2) {
          // block is not UID
          failedBlocks.add(block);
        }
      }

      update((block / totalBlocks * 100).round());
    }

    return failedBlocks.isEmpty;
  }

  @override
  List<int> getFailedBlocks() {
    return failedBlocks;
  }
}
