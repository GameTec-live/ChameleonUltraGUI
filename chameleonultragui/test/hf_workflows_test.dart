import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class RecordingCommunicator extends ChameleonCommunicator {
  RecordingCommunicator() : super(Logger(printer: SimplePrinter()));
  Uint8List? payload;
  Duration? commandTimeout;
  int calls = 0;
  int status = 6;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    calls++;
    payload = data;
    commandTimeout = timeout;
    return ChameleonMessage(
      command: cmd.value,
      status: status,
      data: Uint8List.fromList([0, 32, 0x60, 0, 0, 0]),
    );
  }
}

void main() {
  test('active SELECT keeps all 72 bits and survives trace export/import', () {
    final select = [0x93, 0x70, 1, 2, 3, 4, 4, 0, 0];
    final capture = HfSniffCapture.fromAuthenticationBytes(
      Uint8List.fromList([0, 72, ...select, 0x80, 32, 1, 2, 3, 4]),
    );
    expect(capture.frames.first.bitLength, 72);
    expect(capture.frames.first.data, select);
    expect(capture.frames.last.isCardToReader, isTrue);
    final imported = HfSniffCapture.fromProxmarkTrace(capture.rawBytes);
    expect(imported.frames.first.data, select);
    expect(imported.frames.last.data, [1, 2, 3, 4]);
  });

  test(
    'auth sends key and timeout in firmware order and retains failed trace',
    () async {
      final communicator = RecordingCommunicator();
      final result = await communicator.hf14aAuthTrace(
        255,
        0x61,
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        timeoutMs: 1234,
      );
      expect(communicator.payload, [0x61, 255, 1, 2, 3, 4, 5, 6, 4, 0xD2]);
      expect(communicator.commandTimeout, const Duration(milliseconds: 4234));
      expect(result.status, 6);
      expect(
        HfSniffCapture.fromAuthenticationBytes(result.data).frames,
        hasLength(1),
      );
      for (final block in [-1, 256]) {
        await expectLater(
          communicator.hf14aAuthTrace(block, 0x60, Uint8List(6)),
          throwsRangeError,
        );
      }
      await expectLater(
        communicator.hf14aAuthTrace(0, 0x62, Uint8List(6)),
        throwsArgumentError,
      );
      await expectLater(
        communicator.hf14aAuthTrace(0, 0x60, Uint8List(5)),
        throwsArgumentError,
      );
      await expectLater(
        communicator.hf14aAuthTrace(0, 0x60, Uint8List(6), timeoutMs: 30001),
        throwsRangeError,
      );
      expect(communicator.calls, 1);
    },
  );
}
