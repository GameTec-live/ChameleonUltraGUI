import 'dart:typed_data';

import 'package:chameleonultragui/gui/component/mifare/classic.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen1.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen3.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:provider/provider.dart';

class BaseMifareClassicWriteHelper extends AbstractWriteHelper {
  late MifareClassicRecovery recovery;
  late MifareClassicType type;
  late bool isEV1;

  HFCardInfo? hfInfo;
  MifareClassicInfo? mfcInfo;

  @override
  bool get autoDetect => true;

  BaseMifareClassicWriteHelper(super.communicator,
      {required this.recovery,
      this.type = MifareClassicType.m1k,
      this.isEV1 = false});

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      MifareClassicGen1WriteHelper(communicator, recovery: recovery),
      MifareClassicGen2WriteHelper(communicator, recovery: recovery),
      MifareClassicGen3WriteHelper(communicator, recovery: recovery)
    ];
  }

  @override
  List<AbstractWriteHelper> getAvailableMethodsByPriority() {
    return [
      MifareClassicGen1WriteHelper(communicator, recovery: recovery),
      MifareClassicGen3WriteHelper(communicator, recovery: recovery),
      MifareClassicGen2WriteHelper(communicator, recovery: recovery)
    ];
  }

  @override
  List<dynamic> getExtraData() {
    return [recovery];
  }

  @override
  Future<void> getCardType() async {
    if (!await communicator.isReaderDeviceMode()) {
      await communicator.setReaderDeviceMode(true);
    }

    var mifare = await communicator.detectMf1Support();
    type = MifareClassicType.none;

    if (mifare) {
      type = await mfClassicGetType(communicator);
    }
  }

  // throw errors if developer is doing something wrong

  Future<Uint8List> readBlock(int block) async {
    throw UnimplementedError();
  }

  Future<bool> writeBlock(int block, Uint8List data) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> isMagic(dynamic data) {
    throw UnimplementedError();
  }

  @override
  bool isReady() {
    throw UnimplementedError();
  }

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    List<Uint8List> data = card.data;

    try {
      await communicator.scan14443aTag();
    } catch (e) {
      return false;
    }

    if (data.isEmpty || data[0].isEmpty) {
      if (data.isEmpty) {
        data = [Uint8List(0)];
      }
      data[0] = createBlock0FromSave(card);
    }

    for (var sector = 0;
        sector < mfClassicGetSectorCount(type, isEV1: isEV1);
        sector++) {
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        int blockToWrite = block + mfClassicGetFirstBlockCountBySector(sector);
        if (data.length > blockToWrite && data[blockToWrite].isNotEmpty) {
          if (!(await writeBlock(blockToWrite, data[blockToWrite]))) {
            return false;
          }

          update((blockToWrite / mfClassicGetBlockCount(type) * 100).round());
        }
      }
    }

    return true;
  }

  Uint8List createBlock0FromSave(CardSave card) {
    List<int> block = [];
    Uint8List uid = hexToBytes(card.uid);
    block.addAll(uid);
    if (uid.length == 4) {
      int bcc = 0;

      for (int i = 0; i < 4; i++) {
        bcc ^= uid[i];
      }

      block.add(bcc);
    }

    block.add(card.sak);
    block.addAll(card.atqa.reversed);
    block.addAll(List.generate(16 - block.length, (index) => 0));

    return Uint8List.fromList(block);
  }

  @override
  Future<bool> isCompatible(CardSave card) async {
    CardData magicCard;

    try {
      magicCard = await communicator.scan14443aTag();
    } catch (_) {
      return false;
    }

    if (magicCard.uid.length != hexToBytes(card.uid).length) {
      return false;
    }

    int blockCount =
        mfClassicGetBlockCount(chameleonTagTypeGetMfClassicType(card.tag));
    blockCount--;

    Uint8List data = await communicator.send14ARaw(
        Uint8List.fromList([0x60, blockCount]),
        checkResponseCrc: false);

    if (data.length != 4) {
      return false;
    }

    return true;
  }

  @override
  Future<void> reset() async {
    hfInfo = null;
    mfcInfo = null;
    recovery = MifareClassicRecovery(
        appState: recovery.appState,
        update: recovery.update,
        localizations: recovery.localizations);
    await recovery.initialize();
  }

  @override
  Widget getWriteWidget(BuildContext context, dynamic setState) {
    var localizations = AppLocalizations.of(context)!;

    Future<void> prepareMifareClassic() async {
      var appState = Provider.of<ChameleonGUIState>(context, listen: false);

      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      try {
        CardData card = await appState.communicator!.scan14443aTag();
        bool isMifareClassic = false;
        MifareClassicType mifareClassicType = MifareClassicType.none;

        try {
          isMifareClassic = await appState.communicator!.detectMf1Support();
          mifareClassicType = await mfClassicGetType(appState.communicator!);
        } catch (_) {}

        bool isMifareClassicEV1 = isMifareClassic
            ? (await appState.communicator!
                .mf1Auth(0x45, 0x61, gMifareClassicKeys[3]))
            : false;

        setState(() {
          hfInfo = HFCardInfo();
          mfcInfo = MifareClassicInfo();
        });

        if (isMifareClassic) {
          setState(() {
            mfcInfo!.recovery = getExtraData()[0];
          });
        } else {
          setState(() {
            hfInfo!.cardExist = false;
          });

          return;
        }

        setState(() {
          hfInfo!.uid = bytesToHexSpace(card.uid);
          hfInfo!.sak =
              card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();
          hfInfo!.atqa = bytesToHexSpace(card.atqa);
          hfInfo!.ats = (card.ats.isNotEmpty)
              ? bytesToHexSpace(card.ats)
              : localizations.no;
          mfcInfo!.isEV1 = isMifareClassicEV1;
          mfcInfo!.type = mifareClassicType;
          mfcInfo!.state = (mfcInfo!.type != MifareClassicType.none)
              ? MifareClassicState.checkKeys
              : MifareClassicState.none;
          hfInfo!.tech = isMifareClassic
              ? "Mifare Classic ${mfClassicGetName(mfcInfo!.type, localizations)}${isMifareClassicEV1 ? " EV1" : ""}"
              : localizations.other;
        });
      } catch (_) {
        setState(() {
          hfInfo = HFCardInfo();
          mfcInfo = MifareClassicInfo();
        });

        setState(() {
          hfInfo!.cardExist = false;
        });
      }
    }

    return FutureBuilder(
        future: (hfInfo != null) ? Future.value([]) : prepareMifareClassic(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (hfInfo != null && mfcInfo != null && mfcInfo!.recovery != null) {
            return MifareClassicHelper(
                hfInfo: hfInfo!, mfcInfo: mfcInfo!, allowSave: false);
          } else if (hfInfo != null &&
              mfcInfo != null &&
              mfcInfo!.type == MifareClassicType.none) {
            if (hfInfo!.cardExist) {
              return Text(localizations.not_mifare_classic_card);
            } else {
              return Text(localizations.no_card_found);
            }
          } else {
            return const Column(children: [CircularProgressIndicator()]);
          }
        });
  }
}
