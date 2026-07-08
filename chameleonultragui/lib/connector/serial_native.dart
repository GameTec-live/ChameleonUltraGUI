import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class NativeSerial extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;
  SerialPort? checkPort;
  bool checkDFU = true;
  SerialPortReader? reader;

  NativeSerial({required super.log});

  @override
  bool isManualConnectionSupported() {
    return true;
  }

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
    final hadState = hasConnectionState || port != null || reader != null;
    resetConnectionState();
    if (port != null) {
      reader?.close();
      port?.close();
      reader = null;
      port = null;
      if (hadState) {
        notifyConnectionStateChanged();
      }
      return true;
    }
    if (hadState) {
      notifyConnectionStateChanged();
    }
    return false;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];
    for (final port in await availableDevices()) {
      if (await connectDevice(port, false)) {
        if (onlyDFU) {
          if (checkDFU) {
            output.add(Chameleon(
                port: port,
                device: device,
                type: connectionType,
                dfu: checkDFU));
          }
        } else {
          output.add(Chameleon(
              port: port, device: device, type: connectionType, dfu: checkDFU));
        }
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    if (await connectDevice(devicePort, true)) {
      portName = devicePort;
      connected = true;
      activeDevicePort = devicePort;
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
      
      bool isChameleon = false;
      if (checkPort!.manufacturer == "Proxgrind" ||
          (checkPort!.description != null &&
              checkPort!.description!.toLowerCase().contains("chameleon"))) {
        isChameleon = true;
        if (checkPort!.productName != null &&
            checkPort!.productName!.contains('ChameleonUltra')) {
          device = ChameleonDevice.ultra;
        } else if (checkPort!.description != null &&
            checkPort!.description!.toLowerCase().contains('ultra')) {
          device = ChameleonDevice.ultra;
        } else {
          device = ChameleonDevice.lite;
        }
      } else if (setPort) {
        isChameleon = true;
        device = ChameleonDevice.ultra;
      }

      if (isChameleon) {
        log.d("Found Chameleon ${chameleonDeviceName(device)}!");

        connectionType = ConnectionType.usb;

        checkDFU = checkPort!.vendorId == 0x1915;

        checkPort!.close();

        if (setPort) {
          port = checkPort;
          isDFU = checkDFU;
        }

        return true;
      }

      checkPort!.close();
      return false;
    } on SerialPortError catch (e) {
      log.e(e);
      try {
        checkPort?.close();
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<void> open() async {
    port!.openReadWrite();
    reader = SerialPortReader(port!, timeout: 2500);
    reader?.stream.listen((data) async {
      try {
        await messageCallback(data);
      } catch (_) {
        log.w("Received unexpected data: ${bytesToHex(data)}");
      }
    }, onDone: () async {
      await performDisconnect();
    }, onError: (_) async {
      await performDisconnect();
    });
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    port!.write(command);
    port!.drain();
    return true;
  }
}
