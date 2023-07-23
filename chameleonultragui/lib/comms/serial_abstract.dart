import 'dart:typed_data';
import 'package:logger/logger.dart';

enum ChameleonDevice { none, ultra, lite }

class AbstractSerial {
  Logger log = Logger();
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;
  String portName = "None";
  bool usbConnected = false;

  Future<bool> preformConnection() async {
    return false;
  }

  Future<bool> performDisconnect() async {
    return false;
  }

  Future<List> availableDevices() async {
    return [];
  }

  Future<bool> connectSpecific(device) async {
    return false;
  }

  Future<List> availableChameleons() async {
    return [];
  }

  Future<void> open() async {}

  Future<bool> write(Uint8List command) async {
    return false;
  }

  Future<Uint8List> read(int length) async {
    return Uint8List(0);
  }

  Future<void> finishRead() async {}
}
