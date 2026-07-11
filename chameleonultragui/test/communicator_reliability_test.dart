import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _FakeSerial extends AbstractSerial {
  _FakeSerial() : super(log: Logger(output: MemoryOutput()));

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;
}

void main() {
  test('commands that skip a response do not remain queued', () async {
    final serial = _FakeSerial();
    final communicator = ChameleonCommunicator(serial.log, port: serial);

    await communicator.sendCmd(
      ChameleonCommand.getAppVersion,
      skipReceive: true,
    );

    expect(communicator.commandQueue, isEmpty);
  });

  test('first-run retry terminates after the retry times out', () async {
    final serial = _FakeSerial();
    final communicator = ChameleonCommunicator(serial.log, port: serial);

    await expectLater(
      communicator.sendCmd(
        ChameleonCommand.getAppVersion,
        timeout: const Duration(milliseconds: 5),
        firstRun: true,
      ),
      throwsA(isA<String>()),
    );
    expect(communicator.commandQueue, isEmpty);
  });
}
