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

  Future<bool> write(Uint8List command) async {
    return false;
  }

  Future<Uint8List> read(int length) async {
    return Uint8List(0);
  }

  Future<int> getBatteryCharge() async { // 0-100, get device battery charge
    return 0;
  }

  Future<List<bool>> getUsedSlots() async { // get the used slots on the device, 8 slots, true if used
    return [false, false, false, false, false, false, false, false];
  }

  Future<int> getSelectedSlot() async { // get the selected slot on the device, 0-7 (8 slots)
    return 0;
  }

  Future<bool> pressAbutton() async { // Emulate a press of the A button on the device
    return false;
  }

  Future<bool> pressBbutton() async { // Emulate a press of the B button on the device
    return false;
  }

  Future<String> getFirmwareVersion() async { // Get the firmware version of the device
    return "0.0.0";
  }

  Future<String> getMemoryUsage() async { // Get the memory usage of the device
    return "0/0";
  }

  Future<void> finishRead() async {}
}
