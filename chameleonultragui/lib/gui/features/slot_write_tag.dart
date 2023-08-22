
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

Future<bool> slotWriteTag({
  required ChameleonTagSave card,
  required ChameleonCom connection,
  required int slotIndex,
  required Function(int) onProgress,
}) async {
  if (!card.tag.writable) {
    return false;
  }

  if (card.tag.frequency == ChameleonTagFrequency.hf) {
    onProgress(0);
    await connection.setReaderDeviceMode(false);
    await connection.enableSlot(slotIndex, true);
    await connection.activateSlot(slotIndex);
    await connection.setSlotType(slotIndex, card.tag);
    await connection.setDefaultDataToSlot(slotIndex, card.tag);
    var cardData = ChameleonCard(
        uid: hexToBytes(card.uid.replaceAll(" ", "")),
        atqa: card.atqa,
        sak: card.sak);
    await connection.setMf1AntiCollision(cardData);

    List<int> blockChunk = [];
    int lastSend = 0;

    for (var blockOffset = 0;
        blockOffset <
            mfClassicGetBlockCount(
                chameleonTagTypeGetMfClassicType(card.tag));
        blockOffset++) {
      if ((card.data.length > blockOffset &&
              card.data[blockOffset].isEmpty) ||
          blockChunk.length >= 128) {
        if (blockChunk.isNotEmpty) {
          await connection.setMf1BlockData(
              lastSend, Uint8List.fromList(blockChunk));
          blockChunk = [];
          lastSend = blockOffset;
        }
      }

      if (card.data.length > blockOffset) {
        blockChunk.addAll(card.data[blockOffset]);
      }

      onProgress((blockOffset /
              mfClassicGetBlockCount(
                  chameleonTagTypeGetMfClassicType(card.tag)) *
              100)
          .round());
      await asyncSleep(1);
    }

    if (blockChunk.isNotEmpty) {
      await connection.setMf1BlockData(
          lastSend, Uint8List.fromList(blockChunk));
    }

    onProgress(99);

    await connection.setSlotTagName(
        slotIndex,
        (card.name.isEmpty) ? "No name" : card.name,
        card.tag.frequency);
    await connection.saveSlotData();

    onProgress(100);
    return true;
  }
  
  if (card.tag == ChameleonTag.em410X) {
    onProgress(0);

    await connection.setReaderDeviceMode(false);
    await connection.enableSlot(slotIndex, true);
    await connection.activateSlot(slotIndex);
    await connection.setSlotType(slotIndex, card.tag);
    await connection.setDefaultDataToSlot(slotIndex, card.tag);
    await connection.setEM410XEmulatorID(
        hexToBytes(card.uid.replaceAll(" ", "")));

    onProgress(99);
    await connection.setSlotTagName(
        slotIndex,
        (card.name.isEmpty) ? "No name" : card.name,
        card.tag.frequency);
    await connection.saveSlotData();

    onProgress(100);
    return true;
  }

  return false;
}
