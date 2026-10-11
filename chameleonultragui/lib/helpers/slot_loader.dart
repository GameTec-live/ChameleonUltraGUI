import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf14a4_slot.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

/// Whether [loadCardIntoSlot] knows how to emulate [card].
bool canLoadCardIntoSlot(CardSave card) {
  return isMifareClassic(card.tag) ||
      isMifareUltralight(card.tag) ||
      card.tag == TagType.hf14a4 ||
      isEM410X(card.tag) ||
      card.tag == TagType.hidProx ||
      card.tag == TagType.viking ||
      card.tag == TagType.pac ||
      card.tag == TagType.ioProx ||
      card.tag == TagType.idteck;
}

/// Uploads [card] to emulation slot [slot] (zero based).
///
/// Shared by the desktop slot manager and the mobile UI. [onProgress] receives
/// 0..100 for the card types that upload page/block data. Returns false (and
/// leaves the device untouched) if the card type cannot be emulated yet.
Future<bool> loadCardIntoSlot(
  ChameleonCommunicator communicator,
  int slot,
  CardSave card, {
  required String noName,
  void Function(int progress)? onProgress,
}) async {
  final name = card.name.isEmpty ? noName : card.name;

  if (isMifareClassic(card.tag)) {
    onProgress?.call(0);
    if (chameleonTagSaveCheckForMifareClassicEV1(card)) {
      card.tag = TagType.mifare2K;
    }

    await _prepareSlot(communicator, slot, card.tag, TagFrequency.hf);
    await communicator.setMf1AntiCollision(
      CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats,
      ),
    );

    final blockCount = mfClassicGetBlockCount(
      chameleonTagTypeGetMfClassicType(card.tag),
    );
    List<int> blockChunk = [];
    int lastSend = 0;

    for (var blockOffset = 0; blockOffset < blockCount; blockOffset++) {
      if ((card.data.length > blockOffset && card.data[blockOffset].isEmpty) ||
          blockChunk.length >= 128) {
        if (blockChunk.isNotEmpty) {
          await communicator.setMf1BlockData(
            lastSend,
            Uint8List.fromList(blockChunk),
          );
          blockChunk = [];
          lastSend = blockOffset;
        }
      }

      if (card.data.length > blockOffset &&
          card.data[blockOffset].length == 16) {
        blockChunk.addAll(card.data[blockOffset]);
      }

      onProgress?.call((blockOffset / blockCount * 100).round());
      await asyncSleep(1);
    }

    if (blockChunk.isNotEmpty) {
      await communicator.setMf1BlockData(
        lastSend,
        Uint8List.fromList(blockChunk),
      );
    }

    onProgress?.call(100);
    await communicator.setSlotTagName(slot, name, TagFrequency.hf);
    await communicator.saveSlotData();
  } else if (card.tag == TagType.hf14a4) {
    onProgress?.call(0);
    await _prepareSlot(communicator, slot, card.tag, TagFrequency.hf);
    await writeHf14a4SlotIdentity(communicator, card);
    await communicator.setSlotTagName(slot, name, TagFrequency.hf);
    await communicator.saveSlotData();
    onProgress?.call(100);
  } else if (isMifareUltralight(card.tag)) {
    onProgress?.call(0);
    await _prepareSlot(communicator, slot, card.tag, TagFrequency.hf);
    await communicator.setMf1AntiCollision(
      CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats,
      ),
    );

    final pageCount = mfUltralightGetPagesCount(card.tag);
    for (var page = 0; page < pageCount && card.data.length > page; page++) {
      await communicator.mf0EmulatorWritePages(page, card.data[page]);
      onProgress?.call((page / pageCount * 100).round());
      await asyncSleep(1);
    }

    if (card.extraData.ultralightVersion.isNotEmpty) {
      await communicator.mf0EmulatorSetVersionData(
        card.extraData.ultralightVersion,
      );
    }

    if (card.extraData.ultralightSignature.isNotEmpty) {
      await communicator.mf0EmulatorSetSignatureData(
        card.extraData.ultralightSignature,
      );
    }

    if (card.extraData.ultralightCounters.isNotEmpty) {
      for (int i = 0; i < card.extraData.ultralightCounters.length; i++) {
        await communicator.mf0EmulatorSetCounterData(
          i,
          card.extraData.ultralightCounters[i],
          true,
        );
      }
    }

    if (mfUltralightHasCounters(card.tag)) {
      await communicator.mf0ResetAuthCount();
    }

    onProgress?.call(100);
    await communicator.setSlotTagName(slot, name, TagFrequency.hf);
    await communicator.saveSlotData();
  } else if (isEM410X(card.tag)) {
    final slotTagType = card.tag == TagType.em410XElectra
        ? TagType.em410XElectra
        : TagType.em410X;
    await _prepareSlot(communicator, slot, slotTagType, TagFrequency.lf);
    await communicator.setEM410XEmulatorID(hexToBytes(card.uid));
    await _finishLfSlot(communicator, slot, name);
  } else if (card.tag == TagType.hidProx) {
    await _prepareSlot(communicator, slot, card.tag, TagFrequency.lf);
    await communicator.setHIDProxEmulatorID(
      hexToBytes(HIDCard.fromUID(card.uid).toString()),
    );
    await _finishLfSlot(communicator, slot, name);
  } else if (card.tag == TagType.viking) {
    await _prepareSlot(communicator, slot, card.tag, TagFrequency.lf);
    await communicator.setVikingEmulatorID(hexToBytes(card.uid));
    await _finishLfSlot(communicator, slot, name);
  } else if (card.tag == TagType.pac) {
    await _prepareSlot(communicator, slot, card.tag, TagFrequency.lf);
    await communicator.setPacEmulatorID(hexToBytes(card.uid));
    await _finishLfSlot(communicator, slot, name);
  } else if (card.tag == TagType.ioProx) {
    await _prepareSlot(communicator, slot, card.tag, TagFrequency.lf);
    await communicator.setIoProxEmulatorID(hexToBytes(card.uid));
    await _finishLfSlot(communicator, slot, name);
  } else if (card.tag == TagType.idteck) {
    await _prepareSlot(communicator, slot, card.tag, TagFrequency.lf);
    await communicator.setIdteckEmulatorID(hexToBytes(card.uid));
    await _finishLfSlot(communicator, slot, name);
  } else {
    return false;
  }

  return true;
}

Future<void> _prepareSlot(
  ChameleonCommunicator communicator,
  int slot,
  TagType type,
  TagFrequency frequency,
) async {
  await communicator.setReaderDeviceMode(false);
  await communicator.enableSlot(slot, frequency, true);
  await communicator.activateSlot(slot);
  await communicator.setSlotType(slot, type);
  await communicator.setDefaultDataToSlot(slot, type);
}

Future<void> _finishLfSlot(
  ChameleonCommunicator communicator,
  int slot,
  String name,
) async {
  await communicator.setSlotTagName(slot, name, TagFrequency.lf);
  await communicator.saveSlotData();
}
