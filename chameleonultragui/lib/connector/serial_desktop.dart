import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_native.dart';

/// Combines native USB serial and BLE on Windows, Linux, and macOS.
class DesktopSerial extends AbstractSerial {
  late final BLESerial bleSerial = BLESerial(log: log);
  late final NativeSerial nativeSerial = NativeSerial(log: log);

  DesktopSerial({required super.log}) {
    bleSerial.connectionStateCallback = notifyConnectionStateChanged;
    nativeSerial.connectionStateCallback = notifyConnectionStateChanged;
  }

  @override
  Future<bool> performDisconnect() async =>
      (await bleSerial.performDisconnect()) |
      (await nativeSerial.performDisconnect());

  @override
  bool isManualConnectionSupported() =>
      nativeSerial.isManualConnectionSupported();

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [
        ...await nativeSerial.availableChameleons(onlyDFU),
        ...await bleSerial.availableChameleons(onlyDFU),
      ];

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async =>
      bleSerial.chameleonMap.containsKey(devicePort)
          ? bleSerial.connectSpecificDevice(devicePort)
          : nativeSerial.connectSpecificDevice(devicePort);

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) =>
      bleSerial.connected
          ? bleSerial.write(command, firmware: firmware)
          : nativeSerial.write(command, firmware: firmware);

  @override
  Future<void> registerCallback(dynamic callback) async {
    await bleSerial.registerCallback(callback);
    await nativeSerial.registerCallback(callback);
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
  set isOpen(open) => bleSerial.isOpen = nativeSerial.isOpen = open;
  @override
  bool get isDFU => bleSerial.isDFU || nativeSerial.isDFU;
  @override
  bool get pendingConnection => bleSerial.pendingConnection;
  @override
  set pendingConnection(value) => bleSerial.pendingConnection = value;

  @override
  Future<void> open() =>
      bleSerial.connected ? bleSerial.open() : nativeSerial.open();
}
