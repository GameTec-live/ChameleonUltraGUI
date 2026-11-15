import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter/material.dart';

class BatteryTooltip extends StatelessWidget {
  final BatteryCharge battery;
  final Widget child;

  const BatteryTooltip({super.key, required this.battery, required this.child});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final condition = switch (battery.condition) {
      BatteryCondition.critical => localizations.battery_condition_critical,
      BatteryCondition.low => localizations.battery_condition_low,
      BatteryCondition.fair => localizations.battery_condition_fair,
      BatteryCondition.good => localizations.battery_condition_good,
      BatteryCondition.excellent => localizations.battery_condition_excellent,
      BatteryCondition.unknown => localizations.battery_condition_unknown,
      null => null,
    };
    final info = localizations.battery_info(battery.percent, battery.voltage);
    return Tooltip(
      message: condition == null
          ? info
          : '$info\n${localizations.battery_condition(condition)}',
      child: child,
    );
  }
}
