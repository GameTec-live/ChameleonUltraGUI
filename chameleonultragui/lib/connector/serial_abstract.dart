import 'dart:typed_data';
import 'package:logger/logger.dart';

enum ChameleonDevice { none, ultra, lite }

enum ChameleonConnectType { none, usb, ble, dfu }

class AbstractSerial {
  Logger log = Logger();
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;
  bool isOpen = false;
  String portName = "None";
  ChameleonConnectType connectionType = ChameleonConnectType.none;
  dynamic messageCallback;

  Future<bool> preformConnection() async {
    return false;
  }

  Future<bool> preformDisconnect() async {
    return false;
  }

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

  Future<void> initializeThread() async {}

  Future<void> registerCallback(dynamic callback) async {
    messageCallback = callback;
  }
}
