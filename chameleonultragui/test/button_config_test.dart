import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/chameleon_settings.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

void main() {
  test(
    'button actions retain firmware values and unknown actions fall back',
    () {
      for (final action in ButtonConfig.values) {
        expect(getButtonConfigType(action.value), action);
      }
      expect(ButtonConfig.nfcFieldGenerator.value, 5);
      expect(getButtonConfigType(255), ButtonConfig.disable);
    },
  );

  testWidgets(
    'all four button assignments load, save and reload field generator',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final communicator = _SettingsCommunicator();
      final appState = ChameleonGUIState(SharedPreferencesProvider())
        ..communicator = communicator;
      addTearDown(appState.dispose);

      Future<void> openSettings() async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appState,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: ChameleonSettings()),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await openSettings();
      expect(find.text('NFC field generator'), findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        final selector = find.byType(DropdownButton<ButtonConfig>).at(i);
        expect(
          tester.widget<DropdownButton<ButtonConfig>>(selector).value,
          ButtonConfig.nfcFieldGenerator,
        );

        // Change away and back to prove each callback sends the right command.
        for (final label in ['Disable', 'NFC field generator']) {
          await tester.ensureVisible(selector);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          final option = find.text(label).last;
          await tester.ensureVisible(option);
          await tester.tap(option);
          await tester.pumpAndSettle();
        }
        final command = i < 2
            ? ChameleonCommand.setButtonPressConfig
            : ChameleonCommand.setLongButtonPressConfig;
        final write = communicator.writes[i * 2 + 1];
        expect(write.$1, command);
        expect(write.$2, [i.isEven ? 65 : 66, 5]);
      }
      expect(communicator.saves, 8);

      await tester.pumpWidget(const SizedBox());
      await openSettings();
      for (final selector in tester.widgetList<DropdownButton<ButtonConfig>>(
        find.byType(DropdownButton<ButtonConfig>),
      )) {
        expect(selector.value, ButtonConfig.nfcFieldGenerator);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

// Exercise the real settings encoder/decoder without a connected device.
class _SettingsCommunicator extends ChameleonCommunicator {
  _SettingsCommunicator() : super(Logger(level: Level.off));

  final assignments = [5, 5, 5, 5];
  final writes = <(ChameleonCommand, List<int>)>[];
  var saves = 0;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    var response = <int>[];
    if (cmd == ChameleonCommand.getDeviceSettings) {
      response = [5, 0, ...assignments, 0, ...'123456'.codeUnits];
    } else if (cmd == ChameleonCommand.setButtonPressConfig ||
        cmd == ChameleonCommand.setLongButtonPressConfig) {
      writes.add((cmd, data!.toList()));
      final offset = cmd == ChameleonCommand.setLongButtonPressConfig ? 2 : 0;
      assignments[offset + (data[0] == 65 ? 0 : 1)] = data[1];
    } else if (cmd == ChameleonCommand.saveSettings) {
      saves++;
    }
    return ChameleonMessage(
      command: cmd.value,
      status: 0,
      data: Uint8List.fromList(response),
    );
  }
}
