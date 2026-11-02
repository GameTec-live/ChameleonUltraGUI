import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/hf_reader_settings.dart';
import 'package:chameleonultragui/gui/menu/dialogs/chameleon_settings.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class SettingsCommunicator extends ChameleonCommunicator {
  SettingsCommunicator() : super(Logger());
  int writeStatus = 0;
  final writes = <List<int>>[];

  @override
  Future<DeviceSettings> getDeviceSettings() async => DeviceSettings();

  @override
  Future<List<int>> getDeviceCapabilities() async => [2200, 2201];

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    if (cmd == ChameleonCommand.hf14aSetConfig) writes.add(data!.toList());
    return ChameleonMessage(
      command: cmd.value,
      status: cmd == ChameleonCommand.hf14aSetConfig ? writeStatus : 0,
      data: Uint8List.fromList(
        cmd == ChameleonCommand.hf14aGetConfig ? [1, 2, 0, 1] : [],
      ),
    );
  }
}

Future<void> openSettings(WidgetTester tester, ChameleonGUIState state) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: ChameleonSettings()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('accepted configuration writes preserve firmware field order', () async {
    final communicator = SettingsCommunicator();
    await communicator.hf14aSetConfig(2, 1, 0, 2);
    expect(communicator.writes, [
      [2, 1, 0, 2],
    ]);
  });

  testWidgets('disconnect removes reader controls without a build exception', (
    tester,
  ) async {
    final state = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator = SettingsCommunicator();
    addTearDown(state.dispose);
    await openSettings(tester, state);
    expect(find.byType(HfReaderSettings), findsOneWidget);
    state.communicator = null;
    state.changesMade();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(HfReaderSettings), findsNothing);
  });

  testWidgets('rejected firmware reset shows error and retains loaded values', (
    tester,
  ) async {
    final communicator = SettingsCommunicator()..writeStatus = 0x60;
    final state = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator = communicator;
    addTearDown(state.dispose);
    var changes = 0;
    state.addListener(() => changes++);
    await openSettings(tester, state);
    await tester.ensureVisible(find.text('Reset to default'));
    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(communicator.writes, [
      [0, 0, 0, 0],
    ]);
    expect(find.textContaining('Error:'), findsOneWidget);
    expect(changes, 0);
    expect(
      tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .map((field) => field.initialValue),
      [1, 2, 0, 1],
    );
  });
}
