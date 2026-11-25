import 'package:chameleonultragui/helpers/battery_reading.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero voltage and zero percent is unknown', () {
    expect(
      batteryPercentFromCharge(BatteryCharge(percent: 0, voltage: 0)),
      isNull,
    );
    expect(isLowBattery(null), isFalse);
  });

  test('a real empty battery is not unknown', () {
    final percent = batteryPercentFromCharge(
      BatteryCharge(percent: 0, voltage: 3300),
    );
    expect(percent, 0);
    expect(isLowBattery(percent), isTrue);
  });

  test('normal battery value', () {
    final percent = batteryPercentFromCharge(
      BatteryCharge(percent: 84, voltage: 3900),
    );
    expect(percent, 84);
    expect(isLowBattery(percent), isFalse);
  });

  test('low threshold is below 20 percent', () {
    expect(isLowBattery(19), isTrue);
    expect(isLowBattery(20), isFalse);
  });

  test('retry plan retries after one and three seconds then stops', () {
    final plan = BatteryRetryPlan();
    expect(plan.next(), const Duration(seconds: 1));
    expect(plan.next(), const Duration(seconds: 3));
    expect(plan.next(), isNull);
    plan.reset();
    expect(plan.next(), const Duration(seconds: 1));
  });
}
