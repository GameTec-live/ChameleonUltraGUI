import 'dart:async';
import 'dart:io';

import 'package:chameleonultragui/connector/ble_trace.dart';
import 'package:chameleonultragui/helpers/ble_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const _winrtChannel = MethodChannel('flutter_blue_plus/methods');

/// Triggers the operating system pairing flow when a protected characteristic
/// rejects the link. Windows and Android own the PIN prompt and the bond.
class BlePairingService {
  BlePairingService._();

  static final BlePairingService instance = BlePairingService._();

  /// Set by the Windows connector so USB always wins before a system prompt.
  bool Function()? usbActive;

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
    if (usbActive?.call() == true) {
      BleTrace.instance.log('pair.system.skip', 'reason=usb-active port=$port');
      return Future<bool>.value(false);
    }
    final suppressedUntil = _suppressedUntil;
    if (suppressedUntil != null && DateTime.now().isBefore(suppressedUntil)) {
      BleTrace.instance.log('pair.system.skip', 'reason=cooldown port=$port');
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
    BleTrace.instance.log('pair.system.start', 'port=$port');
    var bonded = await _isBonded(port);
    if (bonded) {
      // CCCD failed although a bond exists, so the stored key is stale.
      try {
        await _winrtChannel.invokeMethod<bool>('removeBond', port);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (_) {}
      bonded = false;
    }
    if (usbActive?.call() == true) {
      BleTrace.instance.log('pair.system.skip', 'reason=usb-active port=$port');
      return false;
    }

    BleStatus.set(BlePhase.pinRequired);
    try {
      final paired = await _winrtChannel
          .invokeMethod<bool>('createBond', {'remote_id': port})
          .timeout(const Duration(seconds: 90));
      BleTrace.instance.log('pair.system.result', 'ok=${paired == true}');
      if (paired == true) {
        if (usbActive?.call() == true) {
          BleTrace.instance.log('pair.system.skip', 'reason=usb-active');
          return false;
        }
        _suppressedUntil = null;
        BleStatus.set(BlePhase.connecting);
        return true;
      }
    } on TimeoutException {
      BleTrace.instance.log('pair.system.timeout', 'port=$port');
    } catch (e) {
      BleTrace.instance.log(
        'pair.system.result',
        'ok=false error=${e.runtimeType}',
      );
    }

    _suppressedUntil = DateTime.now().add(const Duration(seconds: 60));
    BleStatus.set(BlePhase.pinError);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    BleStatus.set(BlePhase.failedRetrying);
    return false;
  }

  Future<bool> _pairAndroid(String port) async {
    BleTrace.instance.log('pair.system.start', 'port=$port');
    try {
      final device = BluetoothDevice.fromId(port);
      if (await _isBonded(port)) {
        return true;
      }
      BleStatus.set(BlePhase.pinRequired);
      await device.createBond(timeout: 30);
      BleStatus.set(BlePhase.connecting);
      BleTrace.instance.log('pair.system.result', 'ok=true');
      return true;
    } catch (e) {
      BleTrace.instance.log(
        'pair.system.result',
        'ok=false error=${e.runtimeType}',
      );
      BleStatus.set(BlePhase.pinError);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      BleStatus.set(BlePhase.failedRetrying);
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