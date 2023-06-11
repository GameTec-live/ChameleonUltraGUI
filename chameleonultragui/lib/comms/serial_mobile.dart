import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:flutter/services.dart';
import 'package:usb_serial/usb_serial.dart';

Future<void> asyncSleep(int milliseconds) async {
  await Future.delayed(Duration(milliseconds: milliseconds));
}

// Class for Android Serial Communication
class MobileSerial extends AbstractSerial {
  Map<String, UsbDevice> deviceMap = {};
  List<Uint8List> messagePool = []; // TODO: Fix or rewrite on release
  UsbPort? port;

  @override
  Future<List> availableDevices() async {
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
  Future<List> availableChameleons() async {
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
      }
      output.add({'port': deviceName, 'device': device});
    }

    return output;
  }

  @override
  Future<bool> connectSpecific(device) async {
    await availableDevices();
    connected = false;
    if (deviceMap.containsKey(device)) {
      port = (await deviceMap[device]!.create())!;
      bool openResult = await port!.open();
      if (!openResult) {
        return false;
      }

      await port!.setRTS(true);
      await port!.setDTR(true);

      port!.setPortParameters(
          115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      connected = true;
      port!.inputStream!.listen((Uint8List data) {
        messagePool.add(data);
      });

      return true;
    }
    return false;
  }

  @override
  Future<bool> write(Uint8List command) async {
    await port!.write(command);
    return true;
  }

  @override
  Future<Uint8List> read(int length) async {
    final completer = Completer<Uint8List>();
    while (true) {
      if (messagePool.isNotEmpty) {
        var message = messagePool[0];
        messagePool.removeWhere((item) => item == message);
        completer.complete(message);
        break;
      }
      await asyncSleep(100);
    }

    return completer.future;
  }
}
