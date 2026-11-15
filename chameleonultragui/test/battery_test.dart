import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/battery_tooltip.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _BatteryCommunicator extends ChameleonCommunicator {
  final bool extended;
  final bool capabilitiesUnavailable;
  final List<int> payload;
  final commands = <ChameleonCommand>[];

  _BatteryCommunicator(
    this.payload, {
    this.extended = true,
    this.capabilitiesUnavailable = false,
  }) : super(Logger(level: Level.off));

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    commands.add(cmd);
    if (cmd == ChameleonCommand.getDeviceCapabilities) {
      if (capabilitiesUnavailable) throw StateError('Unsupported command');
      return ChameleonMessage(
        command: cmd.value,
        status: 0,
        data: Uint8List.fromList(extended ? [0x04, 0x13] : [0x04, 0x01]),
      );
    }
    return ChameleonMessage(
      command: cmd.value,
      status: 0,
      data: Uint8List.fromList(payload),
    );
  }
}

void main() {
  for (final (code, condition) in [
    (0, BatteryCondition.critical),
    (1, BatteryCondition.low),
    (2, BatteryCondition.fair),
    (3, BatteryCondition.good),
    (4, BatteryCondition.excellent),
    (255, BatteryCondition.unknown),
  ]) {
    test('extended response decodes condition $code', () async {
      final communicator = _BatteryCommunicator([0x0F, 0xA0, 75, code]);
      final battery = await communicator.getBatteryCharge();
      expect(battery.voltage, 4000);
      expect(battery.percent, 75);
      expect(battery.condition, condition);
      expect(communicator.commands, [
        ChameleonCommand.getDeviceCapabilities,
        ChameleonCommand.getBatteryChargeEx,
      ]);
      expect(ChameleonCommand.getBatteryChargeEx.value, 1043);
    });
  }

  for (final unavailable in [false, true]) {
    test(
      'legacy response works with unavailable capabilities: $unavailable',
      () async {
        final communicator = _BatteryCommunicator(
          [0x0E, 0x74, 50],
          extended: false,
          capabilitiesUnavailable: unavailable,
        );
        final battery = await communicator.getBatteryCharge();
        expect(battery.voltage, 3700);
        expect(battery.percent, 50);
        expect(battery.condition, isNull);
        expect(communicator.commands.last, ChameleonCommand.getBatteryCharge);
      },
    );
  }

  test('missing optional condition leaves voltage and charge usable', () async {
    final battery = await _BatteryCommunicator([0x0F, 0xA0, 75])
        .getBatteryCharge();
    expect(battery.condition, isNull);
    expect(battery.percent, 75);
  });

  for (final condition in [null, ...BatteryCondition.values]) {
    testWidgets('battery tooltip displays $condition', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Center(
              child: BatteryTooltip(
                battery: BatteryCharge(
                  voltage: 4000,
                  percent: 75,
                  condition: condition,
                ),
                child: const Icon(Icons.battery_5_bar),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.byIcon(Icons.battery_5_bar));
      await tester.pumpAndSettle();
      final suffix = switch (condition) {
        null => '',
        BatteryCondition.critical => '\nCondition: Critical',
        BatteryCondition.low => '\nCondition: Low',
        BatteryCondition.fair => '\nCondition: Fair',
        BatteryCondition.good => '\nCondition: Good',
        BatteryCondition.excellent => '\nCondition: Excellent',
        BatteryCondition.unknown => '\nCondition: Unknown',
      };
      expect(find.text('Charge: 75%\nVoltage: 4000 mV$suffix'), findsOneWidget);
    });
  }
}
