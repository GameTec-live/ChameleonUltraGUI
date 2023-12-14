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

abstract class AbstractSerial {
  late Logger log;
  ChameleonDevice device = ChameleonDevice.none;
  bool connected = false;
  bool isOpen = false;
  bool isDFU = false;
  bool pendingConnection = false;
  String portName = "None";
  ConnectionType connectionType = ConnectionType.none;
  dynamic messageCallback;

  AbstractSerial({required this.log});

  Future<bool> performConnect() async {
    return false;
  }

  Future<bool> performDisconnect() async {
    return false;
  }

  Future<bool> connectSpecificDevice(devicePort);

  Future<List<Chameleon>> availableChameleons(bool onlyDFU);

  Future<void> open() async {}

  Future<bool> write(Uint8List command, {bool firmware = false});

  Future<void> registerCallback(dynamic callback) async {
    messageCallback = callback;
  }
}
