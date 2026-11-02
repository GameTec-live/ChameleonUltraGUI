import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/lf_sniffing.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class CaptureCommunicator extends ChameleonCommunicator {
  CaptureCommunicator() : super(Logger());

  int status = 0x40;
  bool noResponse = false;
  ChameleonCommand? lastCommand;
  Uint8List? lastData;

  @override
  Future<List<int>> getDeviceCapabilities() async => [3009];

  @override
  Future<bool> isReaderDeviceMode() async => true;

  @override
  Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd,
      {Uint8List? data,
      Duration timeout = const Duration(seconds: 5),
      bool skipReceive = false,
      bool firstRun = false}) async {
    lastCommand = cmd;
    lastData = data;
    return noResponse ? null : ChameleonMessage(command: cmd.value, status: status,
        data: Uint8List.fromList(List.generate(800, (i) => i % 64 < 32 ? 16 : 224)));
  }
}

void main() {
  test('ADC capture uses command 3009 without a payload and rejects errors', () async {
    final communicator = CaptureCommunicator();
    expect(await communicator.adcGenericRead(), hasLength(800));
    expect(communicator.lastCommand, ChameleonCommand.adcGenericRead);
    expect(communicator.lastData, isNull);
    communicator.status = 0x67;
    await expectLater(communicator.adcGenericRead(), throwsA(contains('0x67')));
    communicator.noResponse = true;
    await expectLater(communicator.adcGenericRead(), throwsA(contains('No response')));
  });

  testWidgets('ADC-only firmware can capture and adjust analysis ranges', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final communicator = CaptureCommunicator();
    final state = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator = communicator;
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: LfSniffingMenu()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LF ADC read (reader field on)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(communicator.lastCommand, ChameleonCommand.adcGenericRead);
    expect(find.text('800'), findsOneWidget);
    await tester.tap(find.text('Waveform'));
    await tester.pumpAndSettle();
    final start = find.widgetWithText(TextFormField, 'Plot start sample (zero-based)');
    await tester.enterText(start, '100');
    await tester.enterText(find.widgetWithText(TextFormField, 'Samples to plot'), '200');
    await tester.pumpAndSettle();
    expect(find.text('Sample range: 100–300 (end exclusive, 8 µs/sample)'), findsOneWidget);
    await tester.tap(find.text('Decode'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Manchester clock divisor'), '96');
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive clock divisor'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
