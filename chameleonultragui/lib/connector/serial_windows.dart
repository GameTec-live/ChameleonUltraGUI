import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble_windows.dart';
import 'package:chameleonultragui/connector/serial_native.dart';

/// Combines Windows USB serial and BLE serial.
class WindowsSerial extends AbstractSerial {
  late final WindowsBLESerial bleSerial = WindowsBLESerial(log: log);
  late final NativeSerial nativeSerial = NativeSerial(log: log);

  WindowsSerial({required super.log}) {
    bleSerial.connectionStateCallback = notifyConnectionStateChanged;
    nativeSerial.connectionStateCallback = notifyConnectionStateChanged;
    bleSerial.isOtherBusy = () =>
        nativeSerial.connected || nativeSerial.pendingConnection;
    bleSerial.startWatching();
  }

  @override
  Future<bool> performDisconnect() async {
    final ble = await bleSerial.performDisconnect();
    final native = await nativeSerial.performDisconnect();
    return ble || native;
  }

  @override
  bool isManualConnectionSupported() {
    return nativeSerial.isManualConnectionSupported();
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    // BLE is handled by the always-on watcher; the page only lists USB devices.
    return await nativeSerial.availableChameleons(onlyDFU);
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    final port = devicePort.toString();
    if (RegExp(r'^COM\d+$', caseSensitive: false).hasMatch(port)) {
      if (bleSerial.connected || bleSerial.pendingConnection) {
        return false;
      }
      return await nativeSerial.connectSpecificDevice(devicePort);
    }
    if (nativeSerial.connected || nativeSerial.pendingConnection) {
      return false;
    }
    return await bleSerial.connectSpecificDevice(devicePort);
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (bleSerial.connected) {
      return await bleSerial.write(command, firmware: firmware);
    } else {
      return await nativeSerial.write(command, firmware: firmware);
    }
  }

  @override
  Future<void> registerCallback(dynamic callback) async {
    await bleSerial.registerCallback(callback);
    await nativeSerial.registerCallback(callback);
  }

  @override
  Future<void> open() async {
    if (bleSerial.connected) {
      await bleSerial.open();
    } else {
      await nativeSerial.open();
    }
  }

  @override
  dynamic get activeDevicePort => bleSerial.connected
      ? bleSerial.activeDevicePort
      : nativeSerial.activeDevicePort;

  @override
  ChameleonDevice get device =>
      bleSerial.connected ? bleSerial.device : nativeSerial.device;

  @override
  bool get connected => bleSerial.connected || nativeSerial.connected;

  @override
  String get portName =>
      bleSerial.connected ? bleSerial.portName : nativeSerial.portName;

  @override
  ConnectionType get connectionType => bleSerial.connected
      ? bleSerial.connectionType
      : nativeSerial.connectionType;

  @override
  bool get isOpen => bleSerial.isOpen || nativeSerial.isOpen;

  @override
  set isOpen(open) {
    bleSerial.isOpen = open;
    nativeSerial.isOpen = open;
  }

  @override
  bool get isDFU => bleSerial.isDFU || nativeSerial.isDFU;

  @override
  bool get pendingConnection =>
      bleSerial.pendingConnection || nativeSerial.pendingConnection;

  @override
  set pendingConnection(pendingConnection) {
    bleSerial.pendingConnection = pendingConnection;
    nativeSerial.pendingConnection = pendingConnection;
  }
}
