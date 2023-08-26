import 'dart:typed_data';
import 'package:logger/logger.dart';

enum ChameleonDevice { none, ultra, lite }

enum ConnectionType { none, usb, ble, dfu }

class AbstractSerial {
  Logger log = Logger();
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;
  bool isOpen = false;
  String portName = "None";
  ConnectionType connectionType = ConnectionType.none;
  dynamic messageCallback;

  Future<bool> performConnect() async {
    return false;
  }

  Future<bool> performDisconnect() async {
    return false;
  }

  Future<List> availableDevices() async {
    return [];
  }

  Future<bool> connectSpecificDevice(devicePort) async {
    return false;
  }

  Future<List> availableChameleons(bool onlyDFU) async {
    return [];
  }

  Future<void> open() async {}

  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    return false;
  }

  Future<void> initializeThread() async {}

  Future<void> registerCallback(dynamic callback) async {
    messageCallback = callback;
  }
}
