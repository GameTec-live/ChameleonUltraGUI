import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/t55xx/write/base.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

// Record protocol requests while leaving the Jablotron bridge methods intact.
class _JablotronCommunicator extends ChameleonCommunicator {
  Uint8List uid = Uint8List(0);
  final requests = <(ChameleonCommand, Uint8List?)>[];

  _JablotronCommunicator() : super(Logger(level: Level.off));

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    requests.add((cmd, data));
    if (cmd == ChameleonCommand.setJablotronEmulatorID) uid = data!;
    return ChameleonMessage(
      command: cmd.value,
      status: 0,
      data:
          cmd == ChameleonCommand.scanJablotronTag ||
              cmd == ChameleonCommand.getJablotronEmulatorID
          ? uid
          : Uint8List(0),
    );
  }
}

void main() {
  test('jablotronCardId converts raw bytes to decimal via BCD', () {
    // Each byte is read as two BCD digits, concatenated across the 5 bytes.
    expect(
      jablotronCardId(Uint8List.fromList([0x00, 0x12, 0x34, 0x56, 0x78])),
      12345678,
    );
    expect(
      jablotronCardId(Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x00])),
      0,
    );
    expect(
      jablotronCardId(Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x01])),
      1,
    );
  });

  test('JablotronCard exposes type, hex string and decimal card number', () {
    final card = JablotronCard.fromUID('0012345678');

    expect(card.type, TagType.jablotron);
    expect(card.toString(), '00 12 34 56 78');
    expect(card.toViewableString(), '12345678 (00 12 34 56 78)');
  });

  test('JablotronCard round-trips through bytes', () {
    final bytes = Uint8List.fromList([0x00, 0x12, 0x34, 0x56, 0x78]);
    final card = JablotronCard.fromBytes(bytes);

    expect(card.uid, bytes);
    expect(card.type, TagType.jablotron);
  });
  test('Jablotron saved cards retain LF type and display after import', () {
    expect(numberToChameleonTag(180), TagType.jablotron);
    expect(chameleonTagToFrequency(TagType.jablotron), TagFrequency.lf);
    expect(
      getTagTypesByFrequency(TagFrequency.lf),
      contains(TagType.jablotron),
    );
    expect(uidSizeForLfTag(TagType.jablotron), 5);
    final saved = CardSave(
      uid: '00 12 34 56 78',
      name: 'Jablotron',
      tag: TagType.jablotron,
    );
    final imported = CardSave.fromJson(saved.toJson());
    expect(imported.tag, TagType.jablotron);
    expect(
      getLFCardFromUID(imported.tag, imported.uid).toViewableString(),
      '12345678 (00 12 34 56 78)',
    );
  });

  test(
    'Jablotron bridge sends IDs and verifies T55xx writes by reading back',
    () async {
      final communicator = _JablotronCommunicator();
      expect(await communicator.readJablotron(), isNull);
      final uid = hexToBytes('0012345678');
      await communicator.setJablotronEmulatorID(uid);
      expect((await communicator.getJablotronEmulatorID()).uid, uid);
      expect((await communicator.readJablotron())!.uid, uid);
      expect(communicator.requests.take(4).map((r) => r.$1.value), [
        3019,
        5010,
        5011,
        3019,
      ]);
      expect(communicator.requests[1].$2, uid);

      final card = CardSave(
        uid: '00 12 34 56 78',
        name: 'Jablotron',
        tag: TagType.jablotron,
      );
      final writer = BaseT55XXCardHelper(communicator);
      writer.currentKey = '11223344';
      writer.newKey = '55667788';
      expect(await writer.writeData(card, (_) {}), isTrue);
      expect(communicator.requests[4].$1.value, 3020);
      expect(communicator.requests[4].$2, [
        ...uid,
        0x55,
        0x66,
        0x77,
        0x88,
        0x55,
        0x66,
        0x77,
        0x88,
        0x11,
        0x22,
        0x33,
        0x44,
        0,
        0,
        0,
        0,
      ]);
      expect(communicator.requests.last.$1.value, 3019);
      communicator.uid = hexToBytes('0099999999');
      expect(await writer.writeData(card, (_) {}), isFalse);
      communicator.uid = Uint8List(0);
      expect(await writer.writeData(card, (_) {}), isFalse);
    },
  );
}
