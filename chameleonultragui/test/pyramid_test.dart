import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _PyramidCommunicator extends ChameleonCommunicator {
  final int status;
  final Uint8List payload;
  ChameleonCommand? command;

  _PyramidCommunicator(this.status, this.payload)
    : super(Logger(level: Level.off));

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    command = cmd;
    return ChameleonMessage(command: cmd.value, status: status, data: payload);
  }
}

void main() {
  // Expected values from the upstream CLI's pyramid_decode, including its
  // 45-bit sentinel -> 42-bit format mapping and unknown-format fallback.
  final fixtures = [
    ('00010101010101010101014fba92b901', 26, 123, 45678),
    ('00010101010101011c1389d5f2bcf101', 42, 777, 2309737967),
    ('0001010101010101010108010280e501', 30, null, 12345),
  ];

  for (final (raw, format, facility, number) in fixtures) {
    test('Pyramid $format-bit display and saved-card round trip match CLI', () {
      final card = PyramidCard.fromUID(raw);
      expect(card.decoded, (
        formatLength: format,
        facilityCode: facility,
        cardNumber: number,
      ));
      final saved = CardSave(
        uid: card.toString(),
        name: 'Pyramid',
        tag: card.type,
      );
      final restored = CardSave.fromJson(saved.toJson());
      final decoded = getLFCardFromUID(restored.tag, restored.uid);
      expect(decoded, isA<PyramidCard>());
      expect(decoded.uid, card.uid);
      expect(decoded.toViewableString(), contains('$number ($format-bit'));
      expect(decoded.toViewableString(), contains(card.toString()));
    });
  }

  test('Pyramid uses firmware type 202 and a 16-byte LF frame', () {
    expect(numberToChameleonTag(202), TagType.pyramid);
    expect(chameleonTagToFrequency(TagType.pyramid), TagFrequency.lf);
    expect(uidSizeForLfTag(TagType.pyramid), 16);
    expect(() => PyramidCard.fromBytes(Uint8List(15)), throwsFormatException);
  });

  test('Pyramid scan uses command 3021 and preserves the raw frame', () async {
    final raw = hexToBytes(fixtures.first.$1);
    final communicator = _PyramidCommunicator(0x40, raw);
    final card = await communicator.readPyramid();
    expect(communicator.command?.value, 3021);
    expect(card?.uid, raw);
    expect(card?.type, TagType.pyramid);
  });

  test('No tag and unsupported firmware are not Pyramid matches', () async {
    for (final status in [0x41, 0x67, 0x69]) {
      expect(
        await _PyramidCommunicator(status, Uint8List(0)).readPyramid(),
        isNull,
      );
    }
  });
}
