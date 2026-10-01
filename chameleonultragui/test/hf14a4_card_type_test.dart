import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf14a4_slot.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _FakeCommunicator extends ChameleonCommunicator {
  CardData? _identity;

  _FakeCommunicator() : super(Logger());

  @override
  Future<void> setMf1AntiCollision(CardData card) async {
    _identity = CardData(
      uid: Uint8List.fromList(card.uid),
      sak: card.sak,
      atqa: Uint8List.fromList(card.atqa),
      ats: Uint8List.fromList(card.ats),
    );
  }

  @override
  Future<CardData> mf1GetAntiCollData() async {
    final card = _identity!;

    return CardData(
      uid: Uint8List.fromList(card.uid),
      sak: card.sak,
      atqa: Uint8List.fromList(card.atqa),
      ats: Uint8List.fromList(card.ats),
    );
  }
}

void main() {
  test('ISO14443-4 is exposed as a high-frequency card type', () {
    expect(numberToChameleonTag(3000), TagType.hf14a4);
    expect(chameleonTagToFrequency(TagType.hf14a4), TagFrequency.hf);
    expect(
      getTagTypesByFrequency(TagFrequency.hf),
      contains(TagType.hf14a4),
    );
    expect(
      getTagTypesByFrequency(TagFrequency.lf),
      isNot(contains(TagType.hf14a4)),
    );
  });

  test('ISO14443-4 slot identity round-trips UID and ATS', () async {
    final communicator = _FakeCommunicator();
    final original = CardSave(
      uid: '04 01 02 03 04 05 06 07 08 09',
      name: 'ISO card',
      tag: TagType.hf14a4,
      sak: 0x20,
      atqa: Uint8List.fromList([0x03, 0x44]),
      ats: Uint8List.fromList([0x06, 0x75, 0x77, 0x81, 0x02, 0x80]),
    );

    await writeHf14a4SlotIdentity(communicator, original);
    final exported =
        await readHf14a4SlotIdentity(communicator, 'Exported ISO card');

    expect(exported.tag, TagType.hf14a4);
    expect(exported.uid, original.uid);
    expect(exported.sak, original.sak);
    expect(exported.atqa, orderedEquals(original.atqa));
    expect(exported.ats, orderedEquals(original.ats));
    expect(exported.data, isEmpty);
  });
}
