import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

class MifareClassicGen3WriteHelper extends MifareClassicGen2WriteHelper {
  MifareClassicGen3WriteHelper(super.communicator, {required super.recovery});

  @override
  String get name => "gen3";

  static String get staticName => "gen3";

  @override
  Future<bool> isMagic(dynamic data) async {
    try {
      if (!await communicator.detectMf1Support()) {
        return false; // not even Mifare Classic
      }

      Uint8List response = await communicator.send14ARaw(
          Uint8List.fromList([0x30, 0x00]),
          checkResponseCrc: false);

      return response.length == 18; // 16 + 2 byte CRC
    } catch (_) {
      return false;
    }
  }

  @override
  bool isReady() {
    for (var sector = 0;
        sector < mfClassicGetSectorCount(type, isEV1: isEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (recovery.checkMarks[sector + (keyType * 40)] !=
            ChameleonKeyCheckmark.found) {
          return false;
        }
      }
    }

    return true;
  }

  @override
  Future<bool> writeBlockModifier(CardSave card, int block, Uint8List data,
      {bool tryBothKeys = false, bool useGenericKey = false}) async {
    try {
      if (block == 0) {
        return writeGen3Block(card, data);
      } else {
        return writeBlock(block, data,
            tryBothKeys: tryBothKeys, useGenericKey: useGenericKey);
      }
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeGen3Block(CardSave dump, Uint8List data) async {
    CardData card = await communicator.scan14443aTag();
    // Try to write whole block
    await communicator.send14ARaw(
        Uint8List.fromList([0x90, 0xFB, 0xCC, 0xCC, 0x10, ...data]),
        checkResponseCrc: false);

    // Try to write UID only
    await communicator.send14ARaw(
        Uint8List.fromList(
            [0x90, 0xFB, 0xCC, 0xCC, 0x07, ...hexToBytes(dump.uid)]),
        checkResponseCrc: false);

    // Card doesn't respond with anything, just compare UID
    card = await communicator.scan14443aTag();
    return bytesToHex(card.uid) ==
            bytesToHex(data.sublist(0, card.uid.length)) ||
        bytesToHexSpace(card.uid) == dump.uid;
  }
}
