import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/hf_selection.dart';
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
  test('scan parses multiple cards, reversed ATQA and variable ATS', () {
    final cards = parseHfScanCards(
      Uint8List.fromList([
        4,
        1,
        2,
        3,
        4,
        0x04,
        0,
        8,
        0,
        7,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        0x44,
        3,
        0x20,
        2,
        0x75,
        0x77,
      ]),
    );
    expect(cards, hasLength(2));
    expect(cards[0].uid, [1, 2, 3, 4]);
    expect(cards[1].uid, [4, 5, 6, 7, 8, 9, 10]);
    expect(cards[1].atqa, [3, 0x44]);
    expect(cards[1].sak, 0x20);
    expect(cards[1].ats, [0x75, 0x77]);
    expect(parseHfScanCards(Uint8List(0)), isEmpty);
    expect(
      () => parseHfScanCards(Uint8List.fromList([4, 1])),
      throwsFormatException,
    );
    expect(
      () =>
          parseHfScanCards(Uint8List.fromList([4, 1, 2, 3, 4, 4, 0, 8, 2, 1])),
      throwsFormatException,
    );
  });

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

  test('scan distinguishes no tags from firmware failures', () async {
    final communicator = RecordingCommunicator()..status = 1;
    expect(await communicator.scan14443aTagKeep(), isEmpty);
    communicator.status = 0x67;
    await expectLater(communicator.scan14443aTagKeep(), throwsStateError);
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
