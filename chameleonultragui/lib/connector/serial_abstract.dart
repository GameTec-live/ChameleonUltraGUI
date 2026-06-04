import 'package:flutter/foundation.dart';
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
  String name = "Abstract";
  bool hasAllPermissions = true;
  ConnectionType connectionType = ConnectionType.none;
  dynamic messageCallback;
  dynamic activeDevicePort;
  VoidCallback? connectionStateCallback;

  AbstractSerial({required this.log});

  Future<bool> performConnect() async {
    return false;
  }

  Future<bool> performDisconnect() async {
    return false;
  }

  bool isManualConnectionSupported();

  Future<bool> connectSpecificDevice(dynamic devicePort);

  Future<List<Chameleon>> availableChameleons(bool onlyDFU);

  Future<void> open() async {}

  Future<bool> write(Uint8List command, {bool firmware = false});

  Future<void> registerCallback(dynamic callback) async {
    messageCallback = callback;
  }

  @protected
  void resetConnectionState() {
    device = ChameleonDevice.none;
    connected = false;
    isOpen = false;
    isDFU = false;
    pendingConnection = false;
    portName = "None";
    connectionType = ConnectionType.none;
    messageCallback = null;
    activeDevicePort = null;
  }

  @protected
  bool get hasConnectionState =>
      connected ||
      isOpen ||
      isDFU ||
      pendingConnection ||
      portName != "None" ||
      connectionType != ConnectionType.none ||
      device != ChameleonDevice.none ||
      activeDevicePort != null;

  @protected
  void notifyConnectionStateChanged() {
    connectionStateCallback?.call();
  }
}
