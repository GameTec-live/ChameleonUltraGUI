import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class NativeSerial extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;
  SerialPort? checkPort;

  @override
  Future<List> availableDevices() async {
    return SerialPort.availablePorts;
  }

  @override
  Future<bool> preformConnection() async {
    for (final port in await availableDevices()) {
      if (await connectDevice(port, true)) {
        portName = port;
        connectionType = ChameleonConnectType.usb;
        connected = true;
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> performDisconnect() async {
    if (port != null) {
      port?.close();
      connected = false;
      return true;
    }
    connected = false; // For debug button
    return false;
  }

  @override
  Future<List> availableChameleons() async {
    List chamList = [];
    for (final port in await availableDevices()) {
      if (await connectDevice(port, false)) {
        chamList.add({'port': port, 'device': device});
      }
    }

    return chamList;
  }

  @override
  Future<bool> connectSpecific(device) async {
    if (await connectDevice(device, true)) {
      portName = device;
      connectionType = ChameleonConnectType.usb;
      connected = true;
      return true;
    }
    return false;
  }

  Future<bool> connectDevice(String address, bool setPort) async {
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
        if (checkPort!.productName!.startsWith('ChameleonUltra')) {
          device = ChameleonDevice.ultra;
        } else {
          device = ChameleonDevice.lite;
        }

        log.d(
            "Found Chameleon ${device == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}!");
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
  }

  @override
  Future<bool> write(Uint8List command) async {
    return port!.write(command) > 1;
  }

  @override
  Future<Uint8List> read(int length) async {
    Uint8List output = port!.read(length);
    return output;
  }

  @override
  Future<void> finishRead() async {
    port!.close();
  }
}

// https://pub.dev/packages/flutter_libserialport/example <- PC Serial Library