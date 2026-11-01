import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/em4x05_reader.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/em4x05.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

Uint8List _payload({bool em4x69 = true}) => Uint8List.fromList([
  0x80, 0, 0, 0x40, // Configuration, including read-login bit.
  0x89, 0xAB, 0xCD, 0xEF,
  0xFE, 0xDC, 0xBA, 0x98,
  em4x69 ? 1 : 0, 1,
]);

class _Reader extends ChameleonCommunicator {
  _Reader() : super(Logger(level: Level.off));

  bool supported = true;
  bool readerMode = false;
  int status = 0x40;
  Uint8List payload = _payload();
  Uint8List? password;
  Completer<void>? pending;

  @override
  Future<List<int>> getDeviceCapabilities() async =>
      supported ? [ChameleonCommand.scanEM4X05Tag.value] : [];

  @override
  Future<bool> isReaderDeviceMode() async => readerMode;

  @override
  Future<void> setReaderDeviceMode(bool value) async => readerMode = value;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    expect(cmd, ChameleonCommand.scanEM4X05Tag);
    password = data;
    await pending?.future;
    return ChameleonMessage(command: cmd.value, status: status, data: payload);
  }
}

Future<void> _showReader(WidgetTester tester, _Reader reader) async {
  final state = ChameleonGUIState(SharedPreferencesProvider())
    ..communicator = reader;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EM4X05ReaderMenu()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'scan sends big-endian password and preserves both unsigned UID halves',
    () async {
      final reader = _Reader();
      final scan = await reader.scanEM4X05(password: 0xFEDCBA98);
      expect(reader.password, [0xFE, 0xDC, 0xBA, 0x98]);
      expect(scan.tagType, 'EM4x69');
      expect(scan.uidHex, 'FEDCBA9889ABCDEF');
      expect(scan.configHex, '80000040');
      expect(scan.uidBlock, 1);
      expect(scan.loginUsed, isTrue);
      final plain = EM4X05Scan.fromBytes(_payload(em4x69: false));
      expect(plain.tagType, 'EM4x05');
      expect(plain.uidHex, '89ABCDEF');
    },
  );

  test(
    'scan rejects failed statuses, truncated responses and invalid passwords',
    () async {
      final reader = _Reader()..status = 0x41;
      await expectLater(reader.scanEM4X05(), throwsStateError);
      reader.status = 0x40;
      reader.payload = Uint8List(13);
      await expectLater(reader.scanEM4X05(), throwsFormatException);
      await expectLater(reader.scanEM4X05(password: -1), throwsArgumentError);
      await expectLater(
        reader.scanEM4X05(password: 0x100000000),
        throwsArgumentError,
      );
    },
  );

  testWidgets(
    'validates password, enters reader mode and displays scan result',
    (tester) async {
      final reader = _Reader();
      await _showReader(tester, reader);
      await tester.enterText(find.byType(TextFormField), 'bad');
      await tester.tap(find.text('Read Card'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid password'), findsOneWidget);
      expect(reader.password, isNull);
      await tester.enterText(find.byType(TextFormField), 'fedcba98');
      await tester.tap(find.text('Read Card'));
      await tester.pumpAndSettle();
      expect(reader.readerMode, isTrue);
      expect(reader.password, [0xFE, 0xDC, 0xBA, 0x98]);
      expect(find.textContaining('UID: FEDCBA9889ABCDEF'), findsOneWidget);
      expect(find.textContaining('LOGIN used'), findsOneWidget);
    },
  );

  testWidgets('unsupported firmware does not switch mode or scan', (
    tester,
  ) async {
    final reader = _Reader()..supported = false;
    await _showReader(tester, reader);
    await tester.tap(find.text('Read Card'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not support EM4x05'), findsOneWidget);
    expect(reader.readerMode, isFalse);
    expect(reader.password, isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('pending reads disable actions, failure clears stale result', (
    tester,
  ) async {
    final reader = _Reader();
    await _showReader(tester, reader);
    await tester.tap(find.text('Read Card'));
    await tester.pumpAndSettle();
    expect(find.textContaining('UID: '), findsOneWidget);
    reader.pending = Completer<void>();
    reader.status = 0x41;
    await tester.tap(find.text('Read Card'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('UID: '), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    reader.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('scan failed (0x41)'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
