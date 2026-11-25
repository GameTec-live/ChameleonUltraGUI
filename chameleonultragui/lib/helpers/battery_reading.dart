import 'package:chameleonultragui/helpers/definitions.dart';

/// The firmware reports 0 mV/0% before the gauge is ready. A real empty
/// battery still reports a non-zero voltage, so only the all-zero reply is
/// treated as unknown.
int? batteryPercentFromCharge(BatteryCharge battery) {
  if (battery.percent == 0 && battery.voltage == 0) {
    return null;
  }
  return battery.percent;
}

bool isLowBattery(int? percent) => percent != null && percent < 20;

const List<Duration> batteryRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 3),
];

class BatteryRetryPlan {
  int _attempt = 0;

  Duration? next() {
    if (_attempt >= batteryRetryDelays.length) {
      return null;
    }
    return batteryRetryDelays[_attempt++];
  }

  void reset() {
    _attempt = 0;
  }
}
