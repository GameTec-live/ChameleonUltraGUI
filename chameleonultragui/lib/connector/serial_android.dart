import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble.dart' as ble;
import 'package:chameleonultragui/connector/serial_mobile.dart' as mobile;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// Class combines Android OTG and BLE serial
class SerialConnector extends AbstractSerial {
  ble.SerialConnector bleSerial = ble.SerialConnector();
  mobile.SerialConnector mobileSerial = mobile.SerialConnector();

  @override
  Future<bool> preformDisconnect() async {
    bool ble = await bleSerial.preformDisconnect();
    bool otg = await mobileSerial.preformDisconnect();
    return (ble || otg);
  }

  @override
  Future<List> availableChameleons(bool onlyDFU) async {
    List output = [];

    output.addAll(await mobileSerial.availableChameleons(onlyDFU));
    if (await checkPermissions()) {
      output.addAll(await bleSerial.availableChameleons(onlyDFU));
    }

    return output;
  }

  @override
  Future<bool> connectSpecific(devicePort) async {
    if (devicePort.contains(":")) {
      print(devicePort);
      return bleSerial.connectSpecific(devicePort);
    } else {
      return mobileSerial.connectSpecific(devicePort);
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
  Future<Uint8List> read(int length) async {
    if (bleSerial.connected) {
      return bleSerial.read(length);
    } else {
      return mobileSerial.read(length);
    }
  }

  @override
  Future<void> finishRead() async {
    if (bleSerial.connected) {
      return bleSerial.finishRead();
    } else {
      return mobileSerial.finishRead();
    }
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
  ChameleonConnectType get connectionType => (bleSerial.connected)
      ? bleSerial.connectionType
      : mobileSerial.connectionType;
}
