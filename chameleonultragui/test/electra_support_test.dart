import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _MockCommunicator extends ChameleonCommunicator {
  final Map<ChameleonCommand, ChameleonMessage> responses;
  final List<ChameleonCommand> sentCommands = [];

  _MockCommunicator(this.responses) : super(Logger());

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    sentCommands.add(cmd);
    return responses[cmd] ??
        ChameleonMessage(
          command: cmd.value,
          status: 0x68,
          data: Uint8List(0),
        );
  }
}

void main() {
  group('Electra tag support', () {
    test('EM410X parser handles electra payload with type prefix', () {
      final uid = Uint8List.fromList(List.generate(13, (i) => i));
      final payload = Uint8List.fromList([0x00, 0x68, ...uid]);
      final card = EM410XCard.fromBytes(payload);

      expect(card.type, TagType.em410XElectra);
      expect(card.uid, uid);
    });

    test('EM410X parser handles raw electra UID payload', () {
      final uid = Uint8List.fromList(List.generate(13, (i) => 0xA0 + i));
      final card = EM410XCard.fromBytes(uid);

      expect(card.type, TagType.em410XElectra);
      expect(card.uid, uid);
    });

    test('helpers expose electra as EM410X-compatible LF type', () {
      expect(isEM410X(TagType.em410XElectra), isTrue);
      expect(uidSizeForLfTag(TagType.em410XElectra), 13);
    });

    test('writeEM410XtoT55XX routes electra UIDs to command 3006', () async {
      final comm = _MockCommunicator({});
      await comm.writeEM410XtoT55XX(
        Uint8List.fromList(List.generate(13, (i) => i)),
        Uint8List(4),
        [Uint8List(4)],
      );

      expect(
        comm.sentCommands.single,
        ChameleonCommand.writeEM410XElectraToT5577,
      );
    });

    test('getEM410XEmulatorID strips tag type prefix from electra payload',
        () async {
      final uid = Uint8List.fromList(List.generate(13, (i) => 0x10 + i));
      final comm = _MockCommunicator({
        ChameleonCommand.getEM410XemulatorID: ChameleonMessage(
          command: ChameleonCommand.getEM410XemulatorID.value,
          status: 0x68,
          data: Uint8List.fromList([0x00, 0x68, ...uid]),
        ),
      });

      final result = await comm.getEM410XEmulatorID();
      expect(result, uid);
    });
  });
}
