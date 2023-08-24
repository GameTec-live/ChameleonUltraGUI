import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

// ChameleonDevice.unknown means we know the device is a Chameleon just not whether its an ultra or lite
enum ChameleonDevice {
  none('None'),
  unknown('Chameleon'),
  ultra('Chameleon Ultra'),
  lite('Chameleon Lite');

  const ChameleonDevice(this.name);
  final String name;
}

enum ConnectionType { none, usb, ble, dfu }

class ChameleonDevicePort {
  String port;
  ChameleonDevice device;
  ConnectionType type;

  ChameleonDevicePort({
    required this.port,
    required this.device,
    required this.type
  });
}

enum ChameleonVendor {
  proxgrind(0x6868),
  dfu(0x1915);

  const ChameleonVendor(this.value);
  final int value;
}

bool isChameleonVendor(int? vendorId, [ChameleonVendor? vendor, List<ChameleonVendor>? vendors ]) {
  if (vendors == null && vendor != null) {
    vendors = [vendor];
  }

  vendors ??= ChameleonVendor.values;
  return vendors.any((id) {
    return id.value == vendorId;
  });
}

class AbstractSerial {
  Logger log = Logger();
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;
  bool isOpen = false;
  String portName = "None";
  ConnectionType connectionType = ConnectionType.none;
  Function? messageCallback;

  Future<bool> performConnect() async {
    return false;
  }

  @protected
  @mustCallSuper
  Future<bool> performDisconnect() async {
    // Reset state of connected device
    isOpen = false;
    // connected = false; // TODO: should this be unset here too or in child implementations?
    device = ChameleonDevice.none;
    connectionType = ConnectionType.none;
    messageCallback = null;
    return false;
  }

  Future pairDevices() async {} // For web only

  Future<List> availableDevices() async {
    return [];
  }

  Future<bool> connectSpecificDevice(devicePort) async {
    return false;
  }

  Future<List<ChameleonDevicePort>> availableChameleons(bool onlyDFU) async {
    return [];
  }

  Future<void> open() async {}

  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    return false;
  }

  Future<Uint8List> read(int length) async {
    return Uint8List(0);
  }

  Future<void> finishRead() async {}

  Future<void> initializeThread() async {}

  Future<void> registerCallback(Function callback) async {
    messageCallback = callback;
  }
}
