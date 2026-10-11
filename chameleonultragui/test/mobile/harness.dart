import 'dart:typed_data';

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

/// A connector that finds nothing, for the empty "no devices" state.
class NoDevicesSerial extends EmulatorSerial {
  NoDevicesSerial({required super.log});

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];
}

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

class MobileTestEnv {
  MobileTestEnv(this.appState);

  final ChameleonGUIState appState;
}

Future<MobileTestEnv> createEnv({
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

  return MobileTestEnv(appState);
}

Widget buildMobileApp(
  MobileTestEnv env, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(
        value: env.appState.sharedPreferencesProvider,
      ),
      ChangeNotifierProvider.value(value: env.appState),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: brightness,
        ),
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
