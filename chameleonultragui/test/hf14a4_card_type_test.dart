import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf14a4_slot.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _LoopbackSerial extends AbstractSerial {
  Uint8List? _antiCollisionPayload;
  int getAntiCollisionReads = 0;

  _LoopbackSerial(Logger log) : super(log: log);

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  int _lrc(List<int> bytes) {
    int sum = 0;
    for (final byte in bytes) {
      sum = (sum + byte) & 0xFF;
    }
    return (0x100 - sum) & 0xFF;
  }

  Uint8List _response(int command, Uint8List data) {
    final frame = <int>[
      0x11,
      0xEF,
      (command >> 8) & 0xFF,
      command & 0xFF,
      0x00,
      0x00,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
    ];
    frame.add(_lrc(frame.sublist(2, 8)));
    frame.addAll(data);
    frame.add(_lrc(frame));
    return Uint8List.fromList(frame);
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final cmd = (command[2] << 8) | command[3];
    final dataLength = (command[6] << 8) | command[7];
    final payload = Uint8List.fromList(command.sublist(9, 9 + dataLength));

    if (cmd == ChameleonCommand.mf1SetAntiCollision.value) {
      _antiCollisionPayload = Uint8List.fromList(payload);
      await messageCallback(_response(cmd, Uint8List(0)));
      return true;
    }

    if (cmd == ChameleonCommand.mf1GetAntiCollData.value) {
      getAntiCollisionReads++;
      await messageCallback(
          _response(cmd, _antiCollisionPayload ?? Uint8List(0)));
      return true;
    }

    await messageCallback(_response(cmd, Uint8List(0)));
    return true;
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

  test('ISO14443-4 slot identity round-trips through device protocol',
      () async {
    final log = Logger(level: Level.off);
    final serial = _LoopbackSerial(log);
    final communicator = ChameleonCommunicator(log, port: serial);
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
    expect(serial.getAntiCollisionReads, 1);
  });
}
