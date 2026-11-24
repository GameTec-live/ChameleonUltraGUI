import 'package:flutter/foundation.dart';

/// One-line state shown by the connect page.
enum BlePhase { waiting, connecting, pinRequired, pinError, failedRetrying }

class BleStatus {
  BleStatus._();

  static final ValueNotifier<BlePhase> phase = ValueNotifier<BlePhase>(
    BlePhase.waiting,
  );

  static void set(BlePhase value) {
    if (phase.value != value) {
      phase.value = value;
    }
  }
}
