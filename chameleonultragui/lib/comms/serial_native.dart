import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class NativeSerial extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;

  @override
  Future<List> availableDevices() async {
    return SerialPort.availablePorts;
  }

  @override
  Future<bool> preformConnection() async {
    for (final port in await availableDevices()) {
      if (await connectDevice(port)) {
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
      if (await connectDevice(port)) {
        chamList.add({'port': port, 'device': device});
      }
    }
    device = ChameleonDevice.none;
    port?.close();

    return chamList;
  }

  @override
  Future<bool> connectSpecific(device) async {
    if (await connectDevice(device)) {
      connected = true;
      return true;
    }
    return false;
  }

  Future<bool> connectDevice(String address) async {
    log.d("Connecting to $address");
    try {
      port = SerialPort(address);
      port!.openReadWrite();
      log.d("Connected to $address");
      log.d("Manufacturer: ${port!.manufacturer}");
      log.d("Product: ${port!.productName}");
      if (port!.manufacturer == "Proxgrind") {
        if (port!.productName!.startsWith('ChameleonUltra')) {
          device = ChameleonDevice.ultra;
        } else {
          device = ChameleonDevice.lite;
        }

        log.d(
            "Found Chameleon ${device == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}!");
        port!.close();
        return true;
      }

      return false;
    } on SerialPortError {
      return false;
    }
  }

  @override
  Future<bool> write(Uint8List command) async {
    port!.openReadWrite();
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