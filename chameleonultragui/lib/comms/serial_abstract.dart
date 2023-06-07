import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:logger/logger.dart';

enum ChameleonDevice { none, ultra, lite }

class AbstractSerial {
  Logger log = Logger();
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;
  SerialPort? port;

  bool preformConnection() {
    return false;
  }

  bool performDisconnect() {
    return false;
  }

  List availableDevices() {
    return [];
  }

  bool connectSpecific(device) {
    return false;
  }

  List availableChameleons() {
    return [];
  }

  int write(Uint8List command) {
    return 0;
  }

  Uint8List read(int length) {
    return Uint8List(0);
  }

  void finishRead() {}
}
