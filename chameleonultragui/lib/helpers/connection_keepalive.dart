import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:logger/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the Chameleon link healthy while the app is open and connected.
///
/// Firmware note: the device will not enter system-off sleep while BLE is
/// connected (or USB powered). Premature "device sleep" on Android is almost
/// always the phone/OS dropping an idle BLE link first, then the device
/// sleeping ~4s after disconnect.
///
/// This helper:
/// - holds a wakelock while connected + app is in foreground
/// - sends a lightweight command periodically so Android does not kill idle BLE
class ConnectionKeepAlive {
  ConnectionKeepAlive({this.interval = const Duration(seconds: 12)});

  final Duration interval;

  Timer? _timer;
  bool _wakelockHeld = false;
  bool _pingInFlight = false;

  ChameleonCommunicator? _communicator;
  AbstractSerial? _connector;
  Logger? _log;

  bool get isActive => _timer != null;

  /// Sync keep-alive with current connection + app lifecycle state.
  void sync({
    required bool connected,
    required bool appInForeground,
    ChameleonCommunicator? communicator,
    AbstractSerial? connector,
    Logger? log,
    bool forceWakelock = false,
  }) {
    _communicator = communicator;
    _connector = connector;
    _log = log;

    final shouldKeepAlive = connected &&
        appInForeground &&
        communicator != null &&
        connector != null &&
        connector.connected;

    if (shouldKeepAlive || forceWakelock) {
      _setWakelock(true);
    } else {
      _setWakelock(false);
    }

    if (shouldKeepAlive) {
      _ensureTimer();
    } else {
      _stopTimer();
    }
  }

  void dispose() {
    _stopTimer();
    _setWakelock(false);
    _communicator = null;
    _connector = null;
    _log = null;
  }

  void _ensureTimer() {
    if (_timer != null) {
      return;
    }

    _log?.d('Connection keep-alive started (interval=${interval.inSeconds}s)');
    // Immediate ping after connect stabilizes the link, then periodic.
    unawaited(_ping());
    _timer = Timer.periodic(interval, (_) {
      unawaited(_ping());
    });
  }

  void _stopTimer() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _log?.d('Connection keep-alive stopped');
    }
  }

  Future<void> _ping() async {
    final communicator = _communicator;
    final connector = _connector;
    final log = _log;

    if (_pingInFlight ||
        communicator == null ||
        connector == null ||
        !connector.connected) {
      return;
    }

    _pingInFlight = true;
    try {
      // Lightweight firmware command — any successful round-trip keeps BLE busy.
      await communicator.getFirmwareVersion();
    } catch (e) {
      log?.w('Connection keep-alive ping failed: $e');
      // Drop local session so UI returns to Connect and auto-scan can recover.
      try {
        if (connector.connected) {
          await connector.performDisconnect();
        }
      } catch (_) {}
    } finally {
      _pingInFlight = false;
    }
  }

  void _setWakelock(bool enable) {
    if (_wakelockHeld == enable) {
      return;
    }
    _wakelockHeld = enable;
    try {
      WakelockPlus.toggle(enable: enable);
      _log?.d('Wakelock ${enable ? "enabled" : "disabled"}');
    } catch (e) {
      _log?.w('Wakelock toggle failed: $e');
    }
  }
}
