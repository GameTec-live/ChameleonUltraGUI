import 'dart:typed_data';
import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/mifare_value_block.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class RecordingCommunicator extends ChameleonCommunicator {
  RecordingCommunicator() : super(Logger(level: Level.off));
  final calls = <(ChameleonCommand, Uint8List?)>[];
  int status = 0;
  bool supported = true;
  Completer<void>? readerModeGate;
  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    calls.add((cmd, data));
    if (cmd == ChameleonCommand.changeDeviceMode) {
      await readerModeGate?.future;
    }
    final payload = cmd == ChameleonCommand.getDeviceCapabilities
        ? Uint8List.fromList(
            supported ? [0x07, 0xD8, 0x07, 0xD9, 0x07, 0xDB] : [],
          )
        : cmd == ChameleonCommand.mf1ReadBlock
        ? hexToBytes(MifareClassicDumpAnalyzer.intToValueBlock(-42, 4))
        : Uint8List(0);
    return ChameleonMessage(command: cmd.value, status: status, data: payload);
  }
}

Future<void> openDialog(
  WidgetTester tester,
  RecordingCommunicator c, {
  MifareClassicType type = MifareClassicType.m1k,
  bool isEV1 = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MifareValueBlockDialog(communicator: c, type: type, isEV1: isEV1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectOperation(WidgetTester tester, String label) async {
  await tester.tap(
    find.byWidgetPredicate((widget) => widget is DropdownButtonFormField).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'firmware payload uses independent keys and signed network byte order',
    () async {
      final c = RecordingCommunicator();
      await c.manipulateValueBlock(
        4,
        0x60,
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        MifareClassicValueBlockOperator.decrement,
        -2,
        128,
        0x61,
        Uint8List.fromList([6, 5, 4, 3, 2, 1]),
      );
      expect(c.calls.single.$1, ChameleonCommand.mf1ManipulateValueBlock);
      expect(c.calls.single.$2, [
        0x60,
        4,
        1,
        2,
        3,
        4,
        5,
        6,
        0xC0,
        0xFF,
        0xFF,
        0xFF,
        0xFE,
        0x61,
        128,
        6,
        5,
        4,
        3,
        2,
        1,
      ]);
      c.status = 6;
      await expectLater(
        c.manipulateValueBlock(
          4,
          0x60,
          Uint8List(6),
          MifareClassicValueBlockOperator.restore,
          0,
          4,
          0x60,
          Uint8List(6),
        ),
        throwsStateError,
      );
    },
  );

  for (final operation in ['Increment', 'Write value']) {
    testWidgets('$operation uses inputs captured before reader-mode setup', (
      tester,
    ) async {
      final c = RecordingCommunicator()..readerModeGate = Completer<void>();
      await openDialog(tester, c);
      await selectOperation(tester, operation);
      final fields = find.byType(TextFormField);
      if (operation == 'Increment') {
        await tester.enterText(fields.at(2), '8');
        await tester.enterText(fields.at(3), 'A0A1A2A3A4A5');
        await tester.enterText(fields.at(4), '12');
      } else {
        await tester.enterText(fields.at(2), '-12');
        await tester.enterText(fields.at(3), '9');
      }
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, operation),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, operation));
      await tester.pump();
      // Keyboard input can still reach the focused editor while taps are blocked.
      tester.testTextInput.enterText(operation == 'Increment' ? '999' : '255');
      await tester.pump();
      if (operation == 'Increment') {
        tester.widget<TextFormField>(fields.at(2)).controller!.text = '12';
        tester.widget<TextFormField>(fields.at(3)).controller!.text =
            'BBBBBBBBBBBB';
      } else {
        tester.widget<TextFormField>(fields.at(2)).controller!.text = '123';
      }
      c.readerModeGate!.complete();
      await tester.pumpAndSettle();
      if (operation == 'Increment') {
        expect(c.calls.last.$2!.sublist(9), [
          0,
          0,
          0,
          12,
          0x60,
          8,
          0xA0,
          0xA1,
          0xA2,
          0xA3,
          0xA4,
          0xA5,
        ]);
      } else {
        expect(
          c.calls.last.$2!.sublist(8),
          hexToBytes(MifareClassicDumpAnalyzer.intToValueBlock(-12, 9)),
        );
      }
    });
  }

  testWidgets(
    'EV1 extra data blocks are available only for detected EV1 cards',
    (tester) async {
      final c = RecordingCommunicator();
      await openDialog(tester, c, isEV1: true);
      for (final block in ['64', '69']) {
        await tester.enterText(find.byType(TextFormField).first, block);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Read value'));
        await tester.pumpAndSettle();
        expect(c.calls.last.$1, ChameleonCommand.mf1ReadBlock);
        expect(c.calls.last.$2![1], int.parse(block));
      }
      await tester.enterText(find.byType(TextFormField).first, '72');
      c.calls.clear();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Read value'));
      await tester.pumpAndSettle();
      expect(c.calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await openDialog(tester, c);
      await tester.enterText(find.byType(TextFormField).first, '64');
      c.calls.clear();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Read value'));
      await tester.pumpAndSettle();
      expect(c.calls, isEmpty);
    },
  );
  testWidgets('read displays signed live value and address', (tester) async {
    final c = RecordingCommunicator();
    await openDialog(tester, c);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Read value'));
    await tester.pumpAndSettle();
    expect(find.textContaining('-42'), findsOneWidget);
    expect(
      c.calls.map((e) => e.$1),
      containsAllInOrder([
        ChameleonCommand.changeDeviceMode,
        ChameleonCommand.mf1ReadBlock,
      ]),
    );
  });

  testWidgets('increment sends one firmware operation with destination auth', (
    tester,
  ) async {
    final c = RecordingCommunicator();
    await openDialog(tester, c);
    await selectOperation(tester, 'Increment');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), '8');
    await tester.enterText(fields.at(3), 'A0A1A2A3A4A5');
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Increment'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Increment'));
    await tester.pumpAndSettle();
    final payload = c.calls.last.$2!;
    expect(c.calls.last.$1, ChameleonCommand.mf1ManipulateValueBlock);
    expect(payload[8], 0xC1);
    expect(payload.sublist(9, 13), [0, 0, 0, 1]);
    expect(payload.sublist(13), [0x60, 8, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]);
    expect(find.text('Card operation completed.'), findsOneWidget);
  });

  testWidgets('write encodes signed value and redundant address', (
    tester,
  ) async {
    final c = RecordingCommunicator();
    await openDialog(tester, c);
    await selectOperation(tester, 'Write value');
    await tester.enterText(find.byType(TextFormField).at(2), '-2147483648');
    await tester.enterText(find.byType(TextFormField).at(3), '255');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Write value'));
    await tester.pumpAndSettle();
    expect(c.calls.last.$1, ChameleonCommand.mf1WriteBlock);
    expect(
      c.calls.last.$2!.sublist(8),
      hexToBytes(MifareClassicDumpAnalyzer.intToValueBlock(-2147483648, 255)),
    );
  });

  testWidgets('reject trailers, manufacturer block and out of range blocks', (
    tester,
  ) async {
    final c = RecordingCommunicator();
    await openDialog(tester, c, type: MifareClassicType.m4k);
    for (final block in ['0', '3', '127', '143', '255', '256']) {
      await tester.enterText(find.byType(TextFormField).first, block);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Read value'));
      await tester.pumpAndSettle();
      expect(
        c.calls.where((e) => e.$1 == ChameleonCommand.mf1ReadBlock),
        isEmpty,
      );
      expect(find.textContaining('Enter a data block'), findsOneWidget);
    }
  });

  testWidgets('unsupported firmware disables execution', (tester) async {
    final c = RecordingCommunicator()..supported = false;
    await openDialog(tester, c);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });
}
