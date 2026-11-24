import 'dart:async';
import 'dart:io';

import 'package:chameleonultragui/connector/ble_trace.dart';
import 'package:chameleonultragui/helpers/ble_secure_store.dart';
import 'package:chameleonultragui/helpers/ble_status.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const _winrtChannel = MethodChannel('flutter_blue_plus/methods');

/// Coordinates OS-level BLE pairing from the connect path.
///
/// The UI registers [promptPin] and [bringToFront] once. The PIN itself never
/// reaches the log; only stage names are traced.
class BlePairingService {
  BlePairingService._();

  static final BlePairingService instance = BlePairingService._();

  Future<String?> Function(String? error)? promptPin;
  Future<void> Function()? bringToFront;

  Future<bool>? _inFlight;
  String? _inFlightPort;
  DateTime? _suppressedUntil;

  bool isAuthFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('cccd') ||
        text.contains('authentic') ||
        text.contains('accessdenied') ||
        text.contains('access denied') ||
        text.contains('insufficient') ||
        text.contains('not permitted') ||
        text.contains('security');
  }

  /// Returns true when the link is paired (or pairing is unnecessary) and the
  /// caller should retry its GATT operation.
  Future<bool> ensurePair(String port) {
    if (_inFlight != null && _inFlightPort == port) {
      return _inFlight!;
    }
    final suppressedUntil = _suppressedUntil;
    if (suppressedUntil != null && DateTime.now().isBefore(suppressedUntil)) {
      BleTrace.instance.log('pin.prompt.suppressed', 'port=$port');
      return Future<bool>.value(false);
    }
    final future = Platform.isWindows
        ? _pairWindows(port)
        : Platform.isAndroid
        ? _pairAndroid(port)
        : Future<bool>.value(true);
    _inFlight = future;
    _inFlightPort = port;
    return future.whenComplete(() {
      _inFlight = null;
      _inFlightPort = null;
    });
  }

  Future<bool> _pairWindows(String port) async {
    BleTrace.instance.log('pin.pair.start', 'port=$port');
    try {
      await bringToFront?.call();
    } catch (_) {}

    var bonded = await _isBonded(port);
    var pin = await BlePinStore.read(port);
    String? error;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (pin == null) {
        BleStatus.set(BlePhase.pinRequired);
        BleTrace.instance.log('pin.prompt.show', 'attempt=${attempt + 1}');
        final prompt = promptPin;
        if (prompt == null) {
          BleTrace.instance.log('pin.prompt.missing', '');
          BleStatus.set(BlePhase.failedRetrying);
          return false;
        }
        pin = await prompt(error);
        BleTrace.instance.log(
          'pin.prompt.result',
          pin == null ? 'cancelled' : 'entered',
        );
        if (pin == null) {
          _suppressedUntil = DateTime.now().add(const Duration(seconds: 60));
          BleStatus.set(BlePhase.failedRetrying);
          return false;
        }
      } else {
        BleTrace.instance.log('pin.saved.use', 'attempt=${attempt + 1}');
      }

      BleStatus.set(BlePhase.connecting);
      final paired = await _pairWindowsWithPin(
        port,
        pin,
        unpair: bonded || attempt > 0,
      );
      BleTrace.instance.log('pin.pair.result', 'ok=$paired');

      if (paired) {
        _suppressedUntil = null;
        await BlePinStore.save(port, pin);
        BleStatus.set(BlePhase.connecting);
        return true;
      }

      await BlePinStore.clear(port);
      pin = null;
      error = 'pin';
      BleStatus.set(BlePhase.pinError);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      bonded = await _isBonded(port);
    }

    _suppressedUntil = DateTime.now().add(const Duration(seconds: 60));
    BleStatus.set(BlePhase.failedRetrying);
    return false;
  }

  Future<bool> _pairAndroid(String port) async {
    BleTrace.instance.log('pin.pair.start', 'port=$port');
    setBlePhaseSafely(BlePhase.connecting);
    final saved = await BlePinStore.read(port);
    try {
      var device = BluetoothDevice.fromId(port);
      if (await _isBonded(port)) {
        return true;
      }
      BleStatus.set(BlePhase.pinRequired);
      if (saved != null) {
        await device.createBond(
          timeout: 30,
          pin: Uint8List.fromList(saved.codeUnits),
        );
        await BlePinStore.save(port, saved);
      } else {
        await device.createBond(timeout: 30);
      }
      BleStatus.set(BlePhase.connecting);
      BleTrace.instance.log('pin.pair.result', 'ok=true');
      return true;
    } catch (e) {
      BleTrace.instance.log(
        'pin.pair.result',
        'ok=false error=${e.runtimeType}',
      );
      await BlePinStore.clear(port);
      BleStatus.set(BlePhase.pinError);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      BleStatus.set(BlePhase.failedRetrying);
      return false;
    }
  }

  Future<bool> _pairWindowsWithPin(
    String port,
    String pin, {
    required bool unpair,
  }) async {
    if (unpair) {
      try {
        await _winrtChannel.invokeMethod<bool>('removeBond', port);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (_) {}
    }

    try {
      final result = await _winrtChannel
          .invokeMethod<bool>('createBondWithPin', {
            'remote_id': port,
            'pin': pin,
          })
          .timeout(const Duration(seconds: 30));
      return result == true;
    } on TimeoutException {
      BleTrace.instance.log('pin.pair.timeout', 'port=$port');
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isBonded(String port) async {
    if (Platform.isWindows) {
      try {
        final result = await _winrtChannel.invokeMethod<dynamic>(
          'getBondState',
          port,
        );
        if (result is Map) {
          return result['bond_state'] == 2;
        }
      } catch (_) {}
      return false;
    }

    if (Platform.isAndroid) {
      try {
        final state = await BluetoothDevice.fromId(port).bondState.first
            .timeout(const Duration(seconds: 5));
        return state == BluetoothBondState.bonded;
      } catch (_) {}
    }
    return false;
  }
}

void setBlePhaseSafely(BlePhase phase) {
  if (!kIsWeb) {
    BleStatus.set(phase);
  }
}
