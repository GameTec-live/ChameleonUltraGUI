import 'dart:typed_data';

import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen1.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleonultragui/helpers/write.dart';

class BaseMifareClassicMagicCardHelper extends AbstractWriteHelper {
  late MifareClassicRecovery recovery;
  late MifareClassicType type;
  late bool isEV1;

  @override
  bool get autoDetect => true;

  BaseMifareClassicMagicCardHelper(super.communicator,
      {required this.recovery,
      this.type = MifareClassicType.m1k,
      this.isEV1 = false});

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      MifareClassicGen1WriteHelper(communicator, recovery: recovery),
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

    var card = await communicator.scan14443aTag();
    var mifare = await communicator.detectMf1Support();
    type = MifareClassicType.none;

    if (mifare) {
      type = mfClassicGetType(card.atqa, card.sak);
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

  Future<List<Uint8List>> readSector(int sector) async {
    List<Uint8List> data = [];

    for (var block = 0;
        block < mfClassicGetBlockCountBySector(sector);
        block++) {
      data.add(
          await readBlock(block + mfClassicGetFirstBlockCountBySector(sector)));
    }

    return data;
  }

  Future<List<Uint8List>> readCard() async {
    List<Uint8List> data = [];

    for (var sector = 0;
        sector < mfClassicGetSectorCount(type, isEV1: isEV1);
        sector++) {
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        data.add(await readBlock(
            block + mfClassicGetFirstBlockCountBySector(sector)));
      }
    }

    return data;
  }

  @override
  Future<bool> writeData(List<Uint8List> data, dynamic update) async {
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

    if (data.length != mfClassicGetBlockCount(type)) {
      return false;
    }

    return true;
  }

  @override
  Future<void> reset() async {
    recovery = MifareClassicRecovery(
        appState: recovery.appState, update: recovery.update);
  }
}
