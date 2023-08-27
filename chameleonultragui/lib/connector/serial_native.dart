import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class SerialConnector extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;
  SerialPort? checkPort;
  SerialPortReader? reader;

  @override
  Future<List> availableDevices() async {
    return SerialPort.availablePorts;
  }

  @override
  Future<bool> performConnect() async {
    for (final port in await availableDevices()) {
      if (await connectDevice(port, true)) {
        portName = port;
        connected = true;
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> performDisconnect() async {
    super.performDisconnect();

    if (port != null) {
      port?.close();
      reader?.close();
      reader = null;
      connected = false;
      return true;
    }
    connected = false; // For debug button
    return false;
  }

  @override
  Future<List<ChameleonDevicePort>> availableChameleons(bool onlyDFU) async {
    List<ChameleonDevicePort> output = [];
    for (final port in await availableDevices()) {
      if (await connectDevice(port, false)) {
        if (connectionType == ConnectionType.dfu) {
          output.add(ChameleonDevicePort(
              port: port, device: device, type: connectionType));
        } else if (!onlyDFU) {
          output.add(ChameleonDevicePort(
              port: port, device: device, type: connectionType));
        }
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(devicePort) async {
    if (await connectDevice(devicePort, true)) {
      portName = devicePort;
      connected = true;
      return true;
    }
    return false;
  }

  Future<bool> connectDevice(String address, bool setPort) async {
    if (port != null && port!.isOpen && !setPort) {
      log.d("Chameleon is connected now");
    }

    log.d("Connecting to $address");
    try {
      checkPort = SerialPort(address);
      checkPort!.openReadWrite();
      checkPort!.config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..rts = SerialPortRts.flowControl
        ..cts = SerialPortCts.flowControl
        ..dsr = SerialPortDsr.flowControl
        ..dtr = SerialPortDtr.flowControl
        ..setFlowControl(SerialPortFlowControl.rtsCts);
      log.d("Connected to $address");
      log.d("Manufacturer: ${checkPort!.manufacturer}");
      log.d("Product: ${checkPort!.productName}");
      if (checkPort!.manufacturer == "Proxgrind") {
        if (checkPort!.productName!.contains('ChameleonUltra')) {
          device = ChameleonDevice.ultra;
        } else {
          device = ChameleonDevice.lite;
        }

        log.d(
            "Found ${device.name}!");

        connectionType = ConnectionType.usb;

        if (checkPort!.vendorId == ChameleonVendor.dfu.value) {
          connectionType = ConnectionType.dfu;
          log.w("Chameleon is in DFU mode!");
        }

        checkPort!.close();

        if (setPort) {
          port = checkPort;
        }

        return true;
      }

      return false;
    } on SerialPortError {
      return false;
    }
  }

  @override
  Future<void> open() async {
    port!.openReadWrite();
    reader = SerialPortReader(port!, timeout: 2500);
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    port!.write(command);
    port!.drain();
    return true;
  }

  @override
  Future<void> initializeThread() async {
    reader?.stream.listen((data) {
      messageCallback!(data);
    });
  }
}
