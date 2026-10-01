import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _RawCall {
  final Uint8List data;
  final bool autoSelect;
  final bool keepRfField;

  const _RawCall({
    required this.data,
    required this.autoSelect,
    required this.keepRfField,
  });
}

class _FakeCommunicator extends ChameleonCommunicator {
  final bool acceptPassword;
  final List<_RawCall> calls = [];
  bool _authenticated = false;

  _FakeCommunicator({this.acceptPassword = true})
      : super(Logger(level: Level.off));

  @override
  Future<Uint8List> send14ARaw(
    Uint8List data, {
    int respTimeoutMs = 100,
    int? bitLen,
    bool activateRfField = true,
    bool waitResponse = true,
    bool appendCrc = true,
    bool autoSelect = true,
    bool keepRfField = false,
    bool checkResponseCrc = true,
  }) async {
    calls.add(_RawCall(
      data: Uint8List.fromList(data),
      autoSelect: autoSelect,
      keepRfField: keepRfField,
    ));

    if (data.isNotEmpty && data[0] == 0x1B) {
      if (!acceptPassword) {
        return Uint8List(0);
      }
      _authenticated = true;
      return Uint8List.fromList([0x12, 0x34]);
    }

    if (data.length == 2 && data[0] == 0x30) {
      if (_authenticated && autoSelect) {
        // Selecting the tag again loses the password-authenticated session.
        _authenticated = false;
        return Uint8List(0);
      }

      final page = data[1];
      final firstPage = page == 4
          ? <int>[0xDE, 0xAD, 0xBE, 0xEF]
          : page == 43
              ? <int>[0x00, 0x00, 0x00, 0x00]
              : page == 44
                  ? <int>[0x56, 0x78, 0x00, 0x00]
                  : <int>[page, page, page, page];

      if (!keepRfField) {
        _authenticated = false;
      }

      return Uint8List.fromList([
        ...firstPage,
        ...List<int>.filled(12, 0),
      ]);
    }

    return Uint8List(0);
  }
}

void main() {
  test('password-protected NTAG dump keeps auth session for READ commands',
      () async {
    final communicator = _FakeCommunicator();
    final password = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);

    final result = await mfUltralightReadDump(
      communicator,
      TagType.ntag213,
      password: password,
    );

    expect(result.status, MifareUltralightDumpReadStatus.success);
    expect(result.pages, hasLength(45));
    expect(result.pages[4], orderedEquals([0xDE, 0xAD, 0xBE, 0xEF]));

    final authCalls =
        communicator.calls.where((call) => call.data[0] == 0x1B).toList();
    final readCalls =
        communicator.calls.where((call) => call.data[0] == 0x30).toList();

    expect(authCalls, hasLength(1));
    expect(authCalls.single.keepRfField, isTrue);
    expect(readCalls, hasLength(45));
    expect(readCalls.every((call) => !call.autoSelect), isTrue);
    expect(readCalls.take(44).every((call) => call.keepRfField), isTrue);
    expect(readCalls.last.keepRfField, isFalse);
  });

  test('password page preserves the card response instead of entered key',
      () async {
    final communicator = _FakeCommunicator();
    final password = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);

    final result = await mfUltralightReadDump(
      communicator,
      TagType.ntag213,
      password: password,
    );

    expect(result.status, MifareUltralightDumpReadStatus.success);
    expect(result.pages[43], orderedEquals([0x00, 0x00, 0x00, 0x00]));
    expect(result.pages[43], isNot(orderedEquals(password)));
    expect(result.pages[44], orderedEquals([0x56, 0x78, 0x00, 0x00]));
    expect(result.pages[44], isNot(orderedEquals([0x12, 0x34, 0x00, 0x00])));
  });

  test('invalid password stops before reading pages', () async {
    final communicator = _FakeCommunicator(acceptPassword: false);

    final result = await mfUltralightReadDump(
      communicator,
      TagType.ntag213,
      password: Uint8List.fromList([0x00, 0x00, 0x00, 0x00]),
    );

    expect(result.status, MifareUltralightDumpReadStatus.invalidPassword);
    expect(result.pages, isEmpty);
    expect(
      communicator.calls.where((call) => call.data[0] == 0x30),
      isEmpty,
    );
  });
}
