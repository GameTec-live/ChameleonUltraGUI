import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/services.dart';
import 'package:usb_serial/usb_serial.dart';

// Class for Android Serial Communication
class MobileSerial extends AbstractSerial {
  Map<String, UsbDevice> deviceMap = {};
  List<Uint8List> messagePool = [];
  UsbPort? port;

  @override
  Future<bool> preformDisconnect() async {
    device = ChameleonDevice.none;
    connectionType = ChameleonConnectType.none;
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
    connectionType = ChameleonConnectType.none;
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

        if (deviceMap[deviceName]!.vid == 0x1915) {
          connectionType = ChameleonConnectType.dfu;
          log.w("Chameleon is in DFU mode!");
        }
      }
      if (onlyDFU) {
        if (connectionType == ChameleonConnectType.dfu) {
          output.add(
              {'port': deviceName, 'device': device, 'type': connectionType});
        }
      } else {
        output.add(
            {'port': deviceName, 'device': device, 'type': connectionType});
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecific(devicePort) async {
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
        if (messageCallback) {
          await messageCallback(data);
        } else {
          messagePool.add(data);
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
      connectionType = ChameleonConnectType.usb;
      if (deviceMap[devicePort]!.vid == 0x1915) {
        connectionType = ChameleonConnectType.dfu;
        log.w("Chameleon is in DFU mode!");
      }
      return true;
    }
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    await port!.write(command);
    return true;
  }

  @override
  Future<Uint8List> read(int length) async {
    final completer = Completer<Uint8List>();
    while (true) {
      if (messagePool.isNotEmpty) {
        var message = messagePool[0];
        messagePool.remove(message);
        completer.complete(message);
        break;
      }
      await asyncSleep(10);
    }

    return completer.future;
  }

  @override
  Future<void> finishRead() async {
    messagePool = [];
  }
}
