import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/base.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

class MifareClassicGen2WriteHelper extends BaseMifareClassicMagicCardHelper {
  List<int> failedBlocks = [];
  MifareClassicGen2WriteHelper(super.communicator, {required super.recovery});

  @override
  String get name => "Gen2 / Generic";

  static String get staticName => "Gen2 / Generic";

  @override
  Future<bool> isMagic(dynamic data) async {
    try {
      CardSave cardSave = data;
      var card = await communicator.scan14443aTag();
      if (cardSave.uid == bytesToHexSpace(card.uid)) {
        return true; // if UID matches we can assume it is same card
      }

      return false; // we can't check
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
  Future<bool> writeBlock(int block, Uint8List data,
      {bool tryBothKeys = false, bool useGenericKey = false}) async {
    if (await communicator.mf1WriteBlock(
        block,
        0x60,
        (useGenericKey)
            ? gMifareClassicKeys[0]
            : recovery.validKeys[mfClassicGetSectorByBlock(block)],
        data)) {
      return true;
    }

    if (useGenericKey) {
      if (await communicator.mf1WriteBlock(block, 0x60,
          recovery.validKeys[mfClassicGetSectorByBlock(block)], data)) {
        return true;
      }
    }

    if (tryBothKeys) {
      if (await communicator.mf1WriteBlock(
          block,
          0x61,
          (useGenericKey)
              ? gMifareClassicKeys[0]
              : recovery.validKeys[40 + mfClassicGetSectorByBlock(block)],
          data)) {
        return true;
      }

      if (useGenericKey) {
        if (await communicator.mf1WriteBlock(block, 0x60,
            recovery.validKeys[40 + mfClassicGetSectorByBlock(block)], data)) {
          return true;
        }
      }
    }

    return false;
  }

  @override
  Future<bool> writeData(CardSave card, dynamic update) async {
    List<Uint8List> data = card.data;
    List<bool> cleanSectors = List.generate(40, (index) => false);
    failedBlocks = [];

    if (data.isEmpty || data[0].isEmpty) {
      if (data.isEmpty) {
        data = [Uint8List(0)];
      }
      data[0] = createBlock0FromSave(card);
    }

    for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
      var block = mfClassicGetSectorTrailerBlockBySector(sector);
      if (data.length > block && data[block].isNotEmpty) {
        cleanSectors[sector] =
            await writeBlock(block, data[block], tryBothKeys: true);
      }
    }

    for (var sector = 0;
        sector < mfClassicGetSectorCount(type, isEV1: isEV1);
        sector++) {
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        int blockToWrite = block + mfClassicGetFirstBlockCountBySector(sector);
        if (mfClassicGetSectorTrailerBlockBySector(sector) == blockToWrite) {
          continue; // skip sector blocks for now
        }

        if (data.length > blockToWrite && data[blockToWrite].isNotEmpty) {
          if (!(await writeBlock(blockToWrite, data[blockToWrite],
                      useGenericKey: cleanSectors[sector], tryBothKeys: true) &&
                  cleanSectors[sector]) &&
              blockToWrite != 0) {
            failedBlocks.add(blockToWrite);
          }

          update((blockToWrite / mfClassicGetBlockCount(type) * 100).round());
        }
      }
    }

    for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
      var block = mfClassicGetSectorTrailerBlockBySector(sector);
      if (cleanSectors[sector] &&
          data.length > block &&
          data[block].isNotEmpty) {
        if (!(await writeBlock(block, data[block],
            tryBothKeys: true, useGenericKey: true))) {
          // how we went here? We set to default sector trailer and now we can't write to it. Probably card is lost
          return false;
        }
      }
    }

    return failedBlocks.isEmpty;
  }

  @override
  List<dynamic> getExtraData() {
    return [recovery, failedBlocks];
  }

  @override
  bool writeWidgetSupported() {
    return true;
  }
}
