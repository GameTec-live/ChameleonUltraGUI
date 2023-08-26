import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:flutter/services.dart';
import 'package:usb_serial/usb_serial.dart';

// Class for Android Serial Communication
class MobileSerial extends AbstractSerial {
  Map<String, UsbDevice> deviceMap = {};
  UsbPort? port;

  @override
  Future<bool> performDisconnect() async {
    device = ChameleonDevice.none;
    connectionType = ConnectionType.none;
    isOpen = false;
    messageCallback = null;
    if (port != null) {
      port?.close();
      connected = false;
      return true;
    }
    connected = false; // For debug button
    return false;
  }

  @override
  Future<List> availableDevices() async {
    device = ChameleonDevice.none;
    connectionType = ConnectionType.none;
    List<UsbDevice> availableDevices = await UsbSerial.listDevices();
    List output = [];
    deviceMap = {};

    for (var deviceValue in availableDevices) {
      deviceMap[deviceValue.deviceName] = deviceValue;
      output.add(deviceValue.deviceName);
    }

    return output;
  }

  @override
  Future<List> availableChameleons(bool onlyDFU) async {
    List output = [];
    for (var deviceName in await availableDevices()) {
      if (deviceMap[deviceName]!.manufacturerName == "Proxgrind") {
        if (deviceMap[deviceName]!.productName!.startsWith('ChameleonUltra')) {
          device = ChameleonDevice.ultra;
        } else {
          device = ChameleonDevice.lite;
        }

        log.d(
            "Found Chameleon ${device == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}!");

        var dfuMode = deviceMap[deviceName]!.vid == 0x1915;

        if (onlyDFU) {
          if (dfuMode) {
            output.add({
              'port': deviceName,
              'device': device,
              'type': connectionType,
              'dfu': dfuMode
            });
          }
        } else {
          output.add({
            'port': deviceName,
            'device': device,
            'type': connectionType,
            'dfu': dfuMode
          });
        }
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(devicePort) async {
    await availableDevices();
    connected = false;
    if (deviceMap.containsKey(devicePort)) {
      port = (await deviceMap[devicePort]!.create())!;
      if (deviceMap[devicePort]!.productName!.contains('ChameleonUltra')) {
        device = ChameleonDevice.ultra;
      } else {
        device = ChameleonDevice.lite;
      }

      bool openResult = await port!.open();
      if (!openResult) {
        return false;
      }

      await port!.setRTS(true);
      await port!.setDTR(true);

      port!.setPortParameters(
          115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      connected = true;

      port!.inputStream!.listen((Uint8List data) async {
        if (messageCallback != null) {
          await messageCallback(Uint8List.fromList(data));
        }
      });

      UsbSerial.usbEventStream!.listen((event) {
        if (event.event == "android.hardware.usb.action.USB_DEVICE_DETACHED" &&
            event.device!.deviceName == devicePort) {
          log.w("Chameleon disconnected from USB");
          device = ChameleonDevice.none;
          connected = false;
        }
      });

      portName = devicePort.substring(devicePort.length - 15); // Limit length

      isDFU = deviceMap[devicePort]!.vid == 0x1915;
      return true;
    }
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    await port!.write(command);
    return true;
  }
}
