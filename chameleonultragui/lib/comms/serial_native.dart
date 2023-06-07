import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class NativeSerial extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;

  @override
  List availableDevices() {
    return SerialPort.availablePorts;
  }

  @override
  bool preformConnection() {
    for (final port in availableDevices()) {
      if (connectDevice(port)) {
        connected = true;
        return true;
      }
    }
    return false;
  }

  @override
  bool performDisconnect() {
    if (port != null) {
      port?.close();
      connected = false;
      return true;
    }
    connected = false; // For debug button
    return false;
  }

  @override
  List availableChameleons() {
    List chamList = [];
    for (final port in availableDevices()) {
      if (connectDevice(port)) {
        chamList.add({'port': port, 'device': device});
      }
    }
    device = ChameleonDevice.none;
    port?.close();

    return chamList;
  }

  @override
  bool connectSpecific(device) {
    if (connectDevice(device)) {
      connected = true;
      return true;
    }
    return false;
  }

  bool connectDevice(String address) {
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
  int write(Uint8List command) {
    port!.openReadWrite();
    int output = port!.write(command);
    return output;
  }

  @override
  Uint8List read(int length) {
    Uint8List output = port!.read(length);
    return output;
  }

  @override
  void finishRead() {
    port!.close();
  }
}

// https://pub.dev/packages/flutter_libserialport/example <- PC Serial Library