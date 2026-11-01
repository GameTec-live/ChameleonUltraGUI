import 'dart:typed_data';
import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/gui/menu/tools/raw_commands.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class TestSerial extends EmulatorSerial {
  TestSerial() : super(log: Logger(level: Level.off)) {
    connected = true;
    device = ChameleonDevice.ultra;
  }
  final frames = <Uint8List>[];
  bool fail = false;
  bool delayReply = false;
  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    frames.add(command);
    if (fail) throw StateError('Write failed');
    if (!delayReply) await reply(command);
    return true;
  }

  Future<void> reply(Uint8List command) async {
    // Echo a complete protocol frame with an error status, not a canned UI result.
    final modeQuery =
        command[2] * 256 + command[3] == ChameleonCommand.getDeviceMode.value;
    final response = modeQuery
        ? Uint8List.fromList([...command.sublist(0, 9), 1, 0])
        : Uint8List.fromList(command);
    response[5] = modeQuery ? 0 : 0x67;
    if (modeQuery) response[7] = 1;
    response[8] = (-(response.sublist(2, 8).fold(0, (a, b) => a + b))) & 255;
    response[response.length - 1] =
        (-(response.sublist(0, response.length - 1).fold(0, (a, b) => a + b))) &
        255;
    await messageCallback(response);
  }
}

void main() {
  test(
    'numeric commands preserve unsigned IDs, status, payload and release queue',
    () async {
      final serial = TestSerial();
      final bridge = ChameleonCommunicator(serial.log, port: serial);
      final response = await bridge.sendRawCmd(
        0xF123,
        data: Uint8List.fromList([0xAB]),
      );
      expect(response!.command, 0xF123);
      expect(response.status, 0x67);
      expect(response.data, [0xAB]);
      serial.fail = true;
      await expectLater(bridge.sendRawCmd(1000), throwsStateError);
      expect(bridge.commandQueue, isEmpty);
      serial.fail = false;
      await bridge.sendCmd(ChameleonCommand.getAppVersion);
      expect(bridge.commandQueue, isEmpty);
    },
  );

  test('timeout blocks reuse until its late reply is discarded', () async {
    final serial = TestSerial()..delayReply = true;
    final bridge = ChameleonCommunicator(serial.log, port: serial);
    await expectLater(
      bridge.sendRawCmd(
        1000,
        data: Uint8List.fromList([0xAA]),
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(bridge.commandQueue, isEmpty);
    await expectLater(bridge.sendRawCmd(1000), throwsStateError);
    expect(serial.frames, hasLength(1));
    await serial.reply(serial.frames.first);
    expect(bridge.messageQueue, isEmpty);
    serial.delayReply = false;
    final response = await bridge.sendRawCmd(
      1000,
      data: Uint8List.fromList([0xBB]),
    );
    expect(response!.data, [0xBB]);
    expect(serial.frames, hasLength(2));
  });

  Future<TestSerial> open(WidgetTester tester, {bool hf = false}) async {
    final serial = TestSerial();
    final state = ChameleonGUIState(SharedPreferencesProvider())
      ..connector = serial
      ..communicator = ChameleonCommunicator(serial.log, port: serial);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RawCommandsMenu(hf: hf)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return serial;
  }

  testWidgets(
    'device form validates hex then sends and displays firmware error status',
    (tester) async {
      final serial = await open(tester);
      await tester.enterText(find.byType(TextFormField).at(1), 'A');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(serial.frames, isEmpty);
      await tester.enterText(find.byType(TextFormField).at(0), '0xF123');
      await tester.enterText(find.byType(TextFormField).at(1), 'AB CD');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(serial.frames.single.sublist(2, 4), [0xF1, 0x23]);
      expect(find.textContaining('Status: 0x0067'), findsOneWidget);
    },
  );

  testWidgets('HF form encodes options, timeout and seven-bit frame', (
    tester,
  ) async {
    final serial = await open(tester, hf: true);
    await tester.enterText(find.byType(TextFormField).at(0), '26');
    await tester.enterText(find.byType(TextFormField).at(2), '7');
    await tester.ensureVisible(find.text('Append CRC'));
    await tester.tap(find.text('Append CRC'));
    await tester.ensureVisible(find.text('Send'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    final frame = serial.frames.last;
    expect(frame.sublist(2, 4), [0x07, 0xDA]); // 2010
    expect(frame.sublist(9, frame.length - 1), [0xD4, 0x03, 0xE8, 0, 7, 0x26]);
    expect(find.textContaining('Status: 0x0067'), findsOneWidget);
  });
}
