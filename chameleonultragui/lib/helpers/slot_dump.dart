import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

/// Reads the HF (MIFARE Classic / MIFARE Ultralight) dump from the currently
/// active slot's emulator memory and returns it as a [CardSave].
Future<CardSave> readHfDumpFromSlot(
    ChameleonCommunicator communicator, String name, TagType tagType) async {
  CardData data = await communicator.mf1GetAntiCollData();

  if (isMifareUltralight(tagType)) {
    int pageCount = mfUltralightGetPagesCount(tagType);
    List<Uint8List> pages = [];

    for (int page = 0; page < pageCount; page++) {
      pages.add(await communicator.mf0EmulatorReadPages(page, 1));
    }

    CardSaveExtra extraData = CardSaveExtra();

    Uint8List version = await communicator.mf0EmulatorGetVersionData();
    if (version.isNotEmpty) {
      extraData.ultralightVersion = version;
    }

    Uint8List signature = await communicator.mf0EmulatorGetSignatureData();
    if (signature.isNotEmpty) {
      extraData.ultralightSignature = signature;
    }

    if (mfUltralightHasCounters(tagType)) {
      List<int> counters = [];
      int counterCount = mfUltralightGetCounterCount(tagType);

      for (int i = 0; i < counterCount; i++) {
        var counterData = await communicator.mf0EmulatorGetCounterData(i);
        counters.add(counterData.$1);
      }

      if (counters.isNotEmpty) {
        extraData.ultralightCounters = counters;
      }
    }

    return CardSave(
      uid: bytesToHexSpace(data.uid),
      name: name,
      sak: data.sak,
      atqa: data.atqa,
      ats: data.ats,
      tag: tagType,
      data: pages,
      extraData: extraData,
    );
  } else {
    int blockCount =
        mfClassicGetBlockCount(chameleonTagTypeGetMfClassicType(tagType));

    Uint8List binData = Uint8List(blockCount * 16);

    int readCount = 16;
    int binDataIndex = 0;

    for (int currentBlock = 0;
        currentBlock < blockCount;
        currentBlock += readCount) {
      int blocksToRead = (currentBlock + readCount > blockCount)
          ? blockCount - currentBlock
          : readCount;
      Uint8List result =
          await communicator.mf1GetEmulatorBlock(currentBlock, blocksToRead);

      binData.setAll(binDataIndex, result);
      binDataIndex += result.length;
    }

    List<Uint8List> blocks = [];

    for (int i = 0; i < binData.length; i += 16) {
      blocks.add(Uint8List.fromList(binData.sublist(i, i + 16)));
    }

    return CardSave(
      uid: bytesToHexSpace(data.uid),
      name: name,
      sak: data.sak,
      atqa: data.atqa,
      ats: data.ats,
      tag: tagType,
      data: blocks,
    );
  }
}

/// Writes an edited HF (MIFARE Classic / MIFARE Ultralight) dump back into the
/// emulator memory of [slot] and persists it. [onProgress] is called with a
/// value from 0 to 100 while the dump is being uploaded.
Future<void> writeHfDumpToSlot(
    ChameleonCommunicator communicator, int slot, TagType tagType,
    List<Uint8List> dumpData,
    {void Function(int progress)? onProgress}) async {
  await communicator.activateSlot(slot);

  if (isMifareUltralight(tagType)) {
    int pageCount = mfUltralightGetPagesCount(tagType);

    for (var page = 0; page < pageCount && dumpData.length > page; page++) {
      await communicator.mf0EmulatorWritePages(page, dumpData[page]);
      onProgress?.call((page / pageCount * 100).round());
      await asyncSleep(1);
    }
  } else {
    int blockCount =
        mfClassicGetBlockCount(chameleonTagTypeGetMfClassicType(tagType));

    List<int> blockChunk = [];
    int lastSend = 0;

    for (var blockOffset = 0; blockOffset < blockCount; blockOffset++) {
      if ((dumpData.length > blockOffset && dumpData[blockOffset].isEmpty) ||
          blockChunk.length >= 128) {
        if (blockChunk.isNotEmpty) {
          await communicator.setMf1BlockData(
              lastSend, Uint8List.fromList(blockChunk));
          blockChunk = [];
          lastSend = blockOffset;
        }
      }

      if (dumpData.length > blockOffset && dumpData[blockOffset].length == 16) {
        blockChunk.addAll(dumpData[blockOffset]);
      }

      onProgress?.call((blockOffset / blockCount * 100).round());
      await asyncSleep(1);
    }

    if (blockChunk.isNotEmpty) {
      await communicator.setMf1BlockData(
          lastSend, Uint8List.fromList(blockChunk));
    }
  }

  onProgress?.call(100);
  await communicator.saveSlotData();
}
