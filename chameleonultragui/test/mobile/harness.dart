import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/mobile/mobile_shell.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An emulated device that counts the commands written to it.
class CountingSerial extends EmulatorSerial {
  CountingSerial({required super.log});

  int writes = 0;

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) {
    writes++;
    return super.write(command, firmware: firmware);
  }
}

Future<ChameleonGUIState> createAppState({
  AbstractSerial Function(Logger log)? connector,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    // Avoid periodic rescans keeping timers alive during tests.
    'auto_scan_enabled': false,
    ...prefs,
  });
  final provider = SharedPreferencesProvider();
  await provider.load();

  final appState = ChameleonGUIState(provider);
  appState.log = Logger(level: Level.off);
  appState.connector = (connector ?? (log) => EmulatorSerial(log: log))(
    appState.log!,
  );
  appState.connector!.connectionStateCallback =
      appState.onConnectorStateChanged;

  return appState;
}

Widget buildMobileApp(ChameleonGUIState appState, {double textScale = 1.0}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState.sharedPreferencesProvider),
      ChangeNotifierProvider.value(value: appState),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: MobileScope.builder(context, child),
      ),
      home: const MobileShell(),
    ),
  );
}

void setPhoneSize(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps until async device work settled (the emulator answers instantly but
/// commands are chained through futures).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> connectEmulator(
  WidgetTester tester,
  ChameleonGUIState appState,
) async {
  final connector = appState.connector!;
  await connector.connectSpecificDevice('Demo');
  appState.communicator = ChameleonCommunicator(appState.log!, port: connector);
  await connector.registerCallback(appState.communicator!.onSerialMessage);
  appState.changesMade();
  await settle(tester);
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}
