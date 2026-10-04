import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

Future<void> writeHf14a4SlotIdentity(
    ChameleonCommunicator communicator, CardSave card) async {
  await communicator.setMf1AntiCollision(CardData(
    uid: hexToBytes(card.uid),
    atqa: card.atqa,
    sak: card.sak,
    ats: card.ats,
  ));
}

Future<CardSave> readHf14a4SlotIdentity(
    ChameleonCommunicator communicator, String name) async {
  final data = await communicator.mf1GetAntiCollData();

  return CardSave(
    uid: bytesToHexSpace(data.uid),
    name: name,
    sak: data.sak,
    atqa: data.atqa,
    ats: data.ats,
    tag: TagType.hf14a4,
    data: const [],
  );
}
