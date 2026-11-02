import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class _Reader extends ChameleonCommunicator {
  _Reader() : super(Logger());
  int authCalls = 0;
  bool readerMode = false;

  @override
  Future<List<int>> getDeviceCapabilities() async =>
      [2017];
  @override
  Future<bool> isReaderDeviceMode() async => readerMode;
  @override
  Future<void> setReaderDeviceMode(bool mode) async {
    readerMode = mode;
  }

  @override
  Future<ChameleonMessage> hf14aAuthTrace(
    int block,
    int keyType,
    Uint8List key, {
    int timeoutMs = 5000,
  }) async {
    authCalls++;
    return ChameleonMessage(
      command: 2017,
      status: 6,
      data: Uint8List.fromList([0, 32, 0x60, 0, 0, 0]),
    );
  }
}

Future<void> _show(WidgetTester tester, _Reader reader, Widget menu) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: ChameleonGUIState(SharedPreferencesProvider())
        ..communicator = reader,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: menu),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('validates auth inputs and displays partial failed trace', (
    tester,
  ) async {
    final reader = _Reader();
    await _show(
      tester,
      reader,
      const HfSniffingMenu(activeAuthentication: true),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '256');
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    expect(reader.authCalls, 0);
    await tester.enterText(fields.at(0), '4');
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    expect(reader.authCalls, 1);
    expect(reader.readerMode, isTrue);
    expect(
      find.text('Authentication status: 0x6 (0 = success).'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
