
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

Future<bool> slotWriteTag({
  required CardSave card,
  required ChameleonCommunicator communicator,
  required int slotIndex,
  required Function(int) onProgress,
}) async {
  if (!card.tag.writable) {
    return false;
  }

  if (card.tag.frequency == TagFrequency.hf) {
    onProgress(0);

    var isEV1 = chameleonCardSaveCheckForMifareClassicEV1(card);
    if (isEV1) {
      card.tag = TagType.mifare2K;
    }

    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slotIndex, true);
    await communicator.activateSlot(slotIndex);
    await communicator.setSlotType(slotIndex, card.tag);
    await communicator.setDefaultDataToSlot(slotIndex, card.tag);
    var cardData = CardData(
        uid: hexToBytes(card.uid.replaceAll(" ", "")),
        atqa: card.atqa,
        sak: card.sak);
    await communicator.setMf1AntiCollision(cardData);

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
          await communicator.setMf1BlockData(
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
      await communicator.setMf1BlockData(
          lastSend, Uint8List.fromList(blockChunk));
    }

    onProgress(99);

    await communicator.setSlotTagName(
        slotIndex,
        (card.name.isEmpty) ? "No name" : card.name,
        card.tag.frequency);
    await communicator.saveSlotData();

    onProgress(100);
    return true;
  }
  
  if (card.tag == TagType.em410X) {
    onProgress(0);

    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slotIndex, true);
    await communicator.activateSlot(slotIndex);
    await communicator.setSlotType(slotIndex, card.tag);
    await communicator.setDefaultDataToSlot(slotIndex, card.tag);
    await communicator.setEM410XEmulatorID(
        hexToBytes(card.uid.replaceAll(" ", "")));

    onProgress(99);
    await communicator.setSlotTagName(
        slotIndex,
        (card.name.isEmpty) ? "No name" : card.name,
        card.tag.frequency);
    await communicator.saveSlotData();

    onProgress(100);
    return true;
  }

  return false;
}
