import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/t55xx_block_editor.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class _Communicator extends ChameleonCommunicator {
  _Communicator() : super(Logger(level: Level.off));
  final writes = <Uint8List>[];
  int status = 0x40;
  bool supported = true;
  bool reader = false;

  @override
  Future<List<int>> getDeviceCapabilities() async =>
      supported ? [ChameleonCommand.writeT55XX.value] : [];
  @override
  Future<bool> isReaderDeviceMode() async => reader;
  @override
  Future<void> setReaderDeviceMode(bool readerMode) async =>
      reader = readerMode;
  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    expect(cmd, ChameleonCommand.writeT55XX);
    writes.add(data!);
    return ChameleonMessage(
      command: cmd.value,
      status: status,
      data: Uint8List(0),
    );
  }
}

Future<void> _open(WidgetTester tester, _Communicator communicator) async {
  final state = ChameleonGUIState(SharedPreferencesProvider())
    ..communicator = communicator;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: T55xxBlockEditorMenu()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'raw writes match firmware payload and reject invalid input and status',
    () async {
      final c = _Communicator();
      final word = Uint8List.fromList([0x80, 0, 0xAB, 0xFF]);
      await c.writeT55XX(7, word);
      expect(c.writes.single, [7, 0x80, 0, 0xAB, 0xFF, 0, 0, 0, 0, 0, 0]);
      await c.writeT55XX(
        3,
        word,
        page1: true,
        password: Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(c.writes.last, [3, 0x80, 0, 0xAB, 0xFF, 1, 1, 2, 3, 4, 1]);
      for (final (block, page1) in [(-1, false), (8, false), (4, true)]) {
        await expectLater(
          c.writeT55XX(block, word, page1: page1),
          throwsRangeError,
        );
      }
      await expectLater(c.writeT55XX(0, Uint8List(3)), throwsArgumentError);
      await expectLater(
        c.writeT55XX(0, word, password: Uint8List(5)),
        throwsArgumentError,
      );
      expect(c.writes, hasLength(2));
      c.status = 0x60;
      await expectLater(c.writeT55XX(0, word), throwsStateError);
    },
  );

  testWidgets(
    'editor validates input, changes page, authenticates, and reports failures',
    (tester) async {
      final c = _Communicator();
      await _open(tester, c);
      await tester.tap(find.widgetWithText(FilledButton, 'Write'));
      await tester.pumpAndSettle();
      expect(c.writes, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, '89 AB CD EF');
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      expect(find.text('7'), findsNothing);
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '00000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Write'));
      await tester.pumpAndSettle();
      expect(c.reader, isTrue);
      expect(c.writes.single, [3, 0x89, 0xAB, 0xCD, 0xEF, 1, 0, 0, 0, 0, 1]);
      expect(
        find.text(
          'Write command completed. Tag contents have not been verified.',
        ),
        findsOneWidget,
      );
      c.status = 0x67;
      await tester.tap(find.widgetWithText(FilledButton, 'Write'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0x67'), findsOneWidget);
    },
  );

  testWidgets('unsupported firmware cannot write', (tester) async {
    final c = _Communicator()..supported = false;
    await _open(tester, c);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      find.textContaining('does not support raw T55xx writes'),
      findsOneWidget,
    );
    expect(c.writes, isEmpty);
  });
}
