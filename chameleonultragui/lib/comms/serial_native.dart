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
    for(final port in availableDevices()){
      if (connectDevice(port)) {
        connected = true;
        return true;
      }
    }
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
    port!.close();
    return chamList;
  }

  @override
  bool connectSpecific(port) {
    return connectDevice(port);
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
        
        log.d("Found Chameleon ${device == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}!");
        return true;
      }

      return false; 
    } on SerialPortError {
      return false;
    }
  }
}

// https://pub.dev/packages/flutter_libserialport/example <- PC Serial Library