import 'package:logger/logger.dart';

enum ChameleonDevice { none, ultra, lite }

class AbstractSerial {
  Logger log = Logger();
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;

  bool preformConnection() {
    return false;
  }

  List availableDevices() {
    return [];
  }

  void sendCommand(String command) {
    log.d("Sending: $command");
  }
}