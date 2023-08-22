import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class NativeSerial extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;
  SerialPort? checkPort;
  SerialPortReader? reader;

  @override
  Future<List> availableDevices() async {
    return SerialPort.availablePorts;
  }

  @override
  Future<bool> preformConnection() async {
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
  Future<bool> preformDisconnect() async {
    device = ChameleonDevice.none;
    connectionType = ChameleonConnectType.none;
    if (port != null) {
      port?.close();
      reader?.close();
      reader = null;
      isOpen = false;
      connected = false;
      return true;
    }
    connected = false; // For debug button
    return false;
  }

  @override
  Future<List> availableChameleons(bool onlyDFU) async {
    List output = [];
    for (final port in await availableDevices()) {
      if (await connectDevice(port, false)) {
        if (onlyDFU) {
          if (connectionType == ChameleonConnectType.dfu) {
            output
                .add({'port': port, 'device': device, 'type': connectionType});
          }
        } else {
          output.add({'port': port, 'device': device, 'type': connectionType});
        }
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecific(devicePort) async {
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
            "Found Chameleon ${device == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}!");

        connectionType = ChameleonConnectType.usb;

        if (checkPort!.vendorId == 0x1915) {
          connectionType = ChameleonConnectType.dfu;
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
    if (connectionType != ChameleonConnectType.dfu) {
      reader = SerialPortReader(port!, timeout: 1000);
    }
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    return port!.write(command) > 1;
  }

  @override
  Future<Uint8List> read(int length) async {
    if (reader != null) {
      throw ("Listener exists, unable to read");
    }
    Uint8List output = port!.read(length);
    return output;
  }

  @override
  Future<void> finishRead() async {
    port!.close();
  }

  @override
  Future<void> initializeThread() async {
    reader?.stream.listen((data) async {
      await messageCallback(data);
    });
  }
}
