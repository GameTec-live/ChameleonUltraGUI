import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_mobile.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// Class combines Android OTG and BLE serial
class AndroidSerial extends AbstractSerial {
  late BLESerial bleSerial = BLESerial(log: log);
  late MobileSerial mobileSerial = MobileSerial(log: log);

  AndroidSerial({required super.log});

  @override
  Future<bool> performDisconnect() async {
    bool ble = await bleSerial.performDisconnect();
    bool otg = await mobileSerial.performDisconnect();
    return (ble || otg);
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];

    output.addAll(await mobileSerial.availableChameleons(onlyDFU));
    if (await checkPermissions()) {
      output.addAll(await bleSerial.availableChameleons(onlyDFU));
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(devicePort) async {
    if (devicePort.contains(":")) {
      return bleSerial.connectSpecificDevice(devicePort);
    } else {
      return mobileSerial.connectSpecificDevice(devicePort);
    }
  }

  Future<bool> checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect
    ].request();
    for (var status in statuses.entries) {
      if (status.key == Permission.location) {
        if (!status.value.isGranted) return false;
      } else if (status.key == Permission.bluetoothScan) {
        if (!status.value.isGranted) return false;
      } else if (status.key == Permission.bluetoothAdvertise) {
        if (!status.value.isGranted) return false;
      } else if (status.key == Permission.bluetoothConnect) {
        if (!status.value.isGranted) return false;
      }

      return true;
    }

    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (bleSerial.connected) {
      return bleSerial.write(command, firmware: firmware);
    } else {
      return mobileSerial.write(command, firmware: firmware);
    }
  }

  @override
  Future<void> registerCallback(dynamic callback) async {
    bleSerial.messageCallback = callback;
    mobileSerial.messageCallback = callback;
  }

  @override
  ChameleonDevice get device =>
      (bleSerial.connected) ? bleSerial.device : mobileSerial.device;

  @override
  bool get connected => (bleSerial.connected || mobileSerial.connected);

  @override
  String get portName =>
      (bleSerial.connected) ? bleSerial.portName : mobileSerial.portName;

  @override
  ConnectionType get connectionType => (bleSerial.connected)
      ? bleSerial.connectionType
      : mobileSerial.connectionType;

  @override
  bool get isOpen => (bleSerial.isOpen || mobileSerial.isOpen);

  @override
  set isOpen(open) => {bleSerial.isOpen = mobileSerial.isOpen = open};

  @override
  bool get isDFU => (bleSerial.isDFU || mobileSerial.isDFU);

  @override
  bool get pendingConnection => bleSerial.pendingConnection;

  @override
  set pendingConnection(pendingConnection) =>
      {bleSerial.pendingConnection = pendingConnection};
}
