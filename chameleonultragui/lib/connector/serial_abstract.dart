import 'dart:typed_data';
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

enum ChameleonConnectType { none, usb, ble, dfu }

class ChameleonDevicePort {
  String port;
  ChameleonDevice device;
  ChameleonConnectType type;

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
  String portName = "None";
  ChameleonConnectType connectionType = ChameleonConnectType.none;

  get deviceName {
    if (device == ChameleonDevice.ultra) {
      return 'Chameleon Ultra';
    }
    if (device == ChameleonDevice.lite) {
      return 'Chameleon Lite';
    }

    return 'Unknown';
  }

  Future<bool> performConnection() async {
    return false;
  }

  Future<bool> performDisconnect() async {
    return false;
  }

  Future pairDevices() async {} // For web only

  Future<List> availableDevices() async {
    return [];
  }

  Future<bool> connectSpecific(devicePort) async {
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
}
