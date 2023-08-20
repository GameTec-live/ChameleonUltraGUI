import 'dart:typed_data';
import 'package:logger/logger.dart';

enum ChameleonDevice { none, ultra, lite }

enum ChameleonConnectType { none, usb, ble, dfu }

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

  Future<List> availableChameleons(bool onlyDFU) async {
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
