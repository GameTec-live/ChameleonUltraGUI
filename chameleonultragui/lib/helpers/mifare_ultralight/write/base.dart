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
  bool writeLockAndCounter = false;

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: TextFormField(
              controller: keyController,
              decoration: InputDecoration(
                labelText: localizations.key,
                hintMaxLines: 4,
                hintText: localizations.enter_something(localizations.key),
              ),
              inputFormatters: hexFormatter,
              validator: (value) => validateHex(
                value,
                localizations,
                exactBytes: 16,
                fieldName: localizations.key,
                required: true,
              ),
            ),
          ),
          CheckboxListTile(
            value: writeLockAndCounter,
            onChanged: (value) => setState(() {
              writeLockAndCounter = value ?? false;
            }),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(localizations.ulc_write_lock_and_counter),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
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
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: keyController,
            decoration: InputDecoration(
              labelText: localizations.key,
              hintMaxLines: 4,
              hintText: localizations.enter_something(
                localizations.ultralight_key_prompt,
              ),
            ),
            inputFormatters: hexFormatter,
            validator: (value) => validateHex(
              value,
              localizations,
              exactBytes: 4,
              fieldName: localizations.key,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => {
                setState(() {
                  key = keyController.text;
                }),
              },
              child: Text(localizations.next),
            ),
            TextButton(
              onPressed: () => {
                setState(() {
                  key = "";
                }),
              },
              child: Text(localizations.no_key),
            ),
          ],
        ),
      ],
    );
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

    final List<int> pages = [
      for (int page = 0x04; page <= 0x27; page++) page,
      0x2A,
      0x2B,
    ];

    for (int i = 0; i < pages.length; i++) {
      int page = pages[i];
      if (page < card.data.length && card.data[page].length == 4) {
        if (!await communicator.mf0UlcWritePage(
            ulcKey, page, card.data[page])) {
          failedBlocks.add(page);
        }
      }

      update(((i + 1) / pages.length * 100).round());
    }

    Uint8List authKey = ulcKey;
    Uint8List? dumpKeyCardOrder = _ulcDumpKey(card);
    if (dumpKeyCardOrder != null) {
      Uint8List newKey = mfUltralightSwapUlcKeyOrder(dumpKeyCardOrder);
      if (await communicator.mf0UlcSetKey(ulcKey, newKey)) {
        authKey = newKey;
      } else {
        failedBlocks.add(0x2C);
      }
    }

    if (writeLockAndCounter) {
      await writeUlcCounter(card, authKey);
      await writeUlcLockBytes(card, authKey);
    }

    return failedBlocks.isEmpty;
  }

  Future<void> writeUlcCounter(CardSave card, Uint8List authKey) async {
    const int counterPage = 0x29;
    if (card.data.length <= counterPage || card.data[counterPage].length != 4) {
      return;
    }

    Uint8List counter = card.data[counterPage];
    if (counter[0] == 0 && counter[1] == 0) {
      return;
    }

    // Only the first write to a zero counter sets its value, later writes increment it
    Uint8List current =
        await communicator.mf0UlcReadPages(authKey, counterPage, 1);
    if (current.length < 2 || current[0] != 0 || current[1] != 0) {
      failedBlocks.add(counterPage);
      return;
    }

    if (!await communicator.mf0UlcWritePage(authKey, counterPage,
        Uint8List.fromList([counter[0], counter[1], 0, 0]))) {
      failedBlocks.add(counterPage);
    }
  }

  Future<void> writeUlcLockBytes(CardSave card, Uint8List authKey) async {
    const int lockPage = 0x28;
    if (card.data.length <= lockPage || card.data[lockPage].length != 4) {
      return;
    }

    Uint8List lock = card.data[lockPage];
    if (lock[0] == 0 && lock[1] == 0) {
      return;
    }

    if (!await communicator.mf0UlcWritePage(
        authKey, lockPage, Uint8List.fromList([lock[0], lock[1], 0, 0]))) {
      failedBlocks.add(lockPage);
    }
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
