import 'dart:typed_data';
import 'package:logger/logger.dart';

enum ChameleonDevice { none, ultra, lite }

enum ConnectionType { none, usb, ble }

class Chameleon {
  final dynamic port;
  final ChameleonDevice device;
  final ConnectionType type;
  final bool dfu;

  const Chameleon(
      {required this.port,
      required this.device,
      required this.type,
      required this.dfu});
}

class AbstractSerial {
  Logger log = Logger();
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;
  bool isOpen = false;
  bool isDFU = false;
  bool pendingConnection = false;
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

  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    return [];
  }

  Future<void> open() async {}

  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    return false;
  }

  Future<void> registerCallback(dynamic callback) async {
    messageCallback = callback;
  }
}
