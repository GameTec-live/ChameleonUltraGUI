import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
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
  TagType? tagType;

  bool get isUlc => tagType == TagType.ultralightC;

  BaseMifareUltralightWriteHelper(super.communicator, {this.tagType});

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      BaseMifareUltralightWriteHelper(communicator, tagType: tagType),
    ];
  }

  @override
  List<AbstractWriteHelper> getAvailableMethodsByPriority() {
    return [BaseMifareUltralightWriteHelper(communicator, tagType: tagType)];
  }

  @override
  Widget getWriteWidget(BuildContext context, setState) {
    var localizations = AppLocalizations.of(context)!;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    if (isUlc) {
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
                          hintText:
                              localizations.enter_something(localizations.key)),
                      inputFormatters: hexFormatter,
                      validator: (value) => validateHex(value, localizations,
                          exactBytes: 16,
                          fieldName: localizations.key,
                          required: true),
                    )
                  ],
                ))),
        TextButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              setState(() {
                key = keyController.text;
              });
            }
          },
          child: Text(localizations.next),
        ),
      ]);
    }

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
                    inputFormatters: hexFormatter,
                    validator: (value) => validateHex(value, localizations,
                        exactBytes: 4, fieldName: localizations.key),
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

  Uint8List? _ulcDumpKey(CardSave card) {
    const int firstKeyPage = 0x2C;
    if (card.data.length <= firstKeyPage + 3) {
      return null;
    }

    List<int> stored = [];
    for (int page = firstKeyPage; page <= firstKeyPage + 3; page++) {
      if (card.data[page].length != 4) {
        return null;
      }
      stored.addAll(card.data[page]);
    }

    if (stored.every((byte) => byte == 0)) {
      return null;
    }

    return Uint8List.fromList(stored);
  }

  Future<bool> writeUlcData(
      CardSave card, Function(int writeProgress) update) async {
    failedBlocks = [];

    if (!await communicator.isReaderDeviceMode()) {
      await communicator.setReaderDeviceMode(true);
    }

    if (await communicator.scan14443aTag() == null) {
      return false;
    }

    Uint8List ulcKey = hexToBytes(key ?? "");
    if (ulcKey.length != 16 || !await communicator.mf0UlcAuth(ulcKey)) {
      return false;
    }

    const int firstPage = 0x04;
    const int lastPage = 0x27;

    for (int page = firstPage; page <= lastPage; page++) {
      if (page < card.data.length && card.data[page].length == 4) {
        if (!await communicator.mf0UlcWritePage(
            ulcKey, page, card.data[page])) {
          failedBlocks.add(page);
        }
      }

      update(
          ((page - firstPage + 1) / (lastPage - firstPage + 1) * 100).round());
    }

    Uint8List? dumpKeyCardOrder = _ulcDumpKey(card);
    if (dumpKeyCardOrder != null) {
      Uint8List newKey = mfUltralightSwapUlcKeyOrder(dumpKeyCardOrder);
      if (!await communicator.mf0UlcSetKey(ulcKey, newKey)) {
        failedBlocks.add(0x2C);
      }
    }

    return failedBlocks.isEmpty;
  }

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    if (isUlc) {
      return writeUlcData(card, update);
    }

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

    for (var pass = 0; pass < 2; pass++) {
      for (var block = 0; block < totalBlocks; block++) {
        if (card.data[block].isNotEmpty) {
          List<int> blockData = List.from(card.data[block]);

          if (pass == 0) {
            if (block == 2 && blockData.length >= 4) {
              blockData[2] = 0x00;
              blockData[3] = 0x00;
            }

            if (block == 3) {
              blockData = Uint8List(4);
            }
          } else if (![2, 3].contains(block)) {
            continue;
          }

          Uint8List write = await communicator.send14ARaw(
              Uint8List.fromList([0xA2, block, ...blockData]),
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

          update((block / (totalBlocks + 2) * 100).round());
        }
      }
    }

    return failedBlocks.isEmpty;
  }

  @override
  List<int> getFailedBlocks() {
    return failedBlocks;
  }
}
