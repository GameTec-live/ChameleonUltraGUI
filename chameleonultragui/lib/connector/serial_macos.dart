import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_native.dart';

// Class combines macOS Native Serial and BLE serial
class MacOSSerial extends AbstractSerial {
  late BLESerial bleSerial = BLESerial(log: log);
  late NativeSerial nativeSerial = NativeSerial(log: log);

  MacOSSerial({required super.log});

  @override
  Future<bool> performDisconnect() async {
    bool ble = await bleSerial.performDisconnect();
    bool native = await nativeSerial.performDisconnect();
    return (ble || native);
  }

  @override
  bool isManualConnectionSupported() {
    return nativeSerial.isManualConnectionSupported();
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];

    output.addAll(await nativeSerial.availableChameleons(onlyDFU));
    output.addAll(await bleSerial.availableChameleons(onlyDFU));

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    if (devicePort.contains(":")) {
      return bleSerial.connectSpecificDevice(devicePort);
    } else {
      return nativeSerial.connectSpecificDevice(devicePort);
    }
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (bleSerial.connected) {
      return bleSerial.write(command, firmware: firmware);
    } else {
      return nativeSerial.write(command, firmware: firmware);
    }
  }

  @override
  Future<void> registerCallback(dynamic callback) async {
    bleSerial.messageCallback = callback;
    nativeSerial.messageCallback = callback;
  }

  @override
  ChameleonDevice get device =>
      (bleSerial.connected) ? bleSerial.device : nativeSerial.device;

  @override
  bool get connected => (bleSerial.connected || nativeSerial.connected);

  @override
  String get portName =>
      (bleSerial.connected) ? bleSerial.portName : nativeSerial.portName;

  @override
  ConnectionType get connectionType => (bleSerial.connected)
      ? bleSerial.connectionType
      : nativeSerial.connectionType;

  @override
  bool get isOpen => (bleSerial.isOpen || nativeSerial.isOpen);

  @override
  set isOpen(open) => {bleSerial.isOpen = nativeSerial.isOpen = open};

  @override
  bool get isDFU => (bleSerial.isDFU || nativeSerial.isDFU);

  @override
  bool get pendingConnection => bleSerial.pendingConnection;

  @override
  set pendingConnection(pendingConnection) =>
      {bleSerial.pendingConnection = pendingConnection};
}
