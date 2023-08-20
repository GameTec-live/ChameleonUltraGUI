import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:serial/serial.dart';

class DeviceInfo {
  final SerialPort port;
  final SerialPortInfo info;
  ChameleonDevice _type = ChameleonDevice.ultra;

  DeviceInfo(this.port, this.info);

  get deviceName {
    if (type == ChameleonDevice.ultra) {
      return 'Ultra';
    }
    if (type == ChameleonDevice.lite) {
      return 'Lite';
    }

    return 'Unknown';
  }

  ChameleonDevice get type {
    return _type;
  }

  set type(ChameleonDevice dev) => {
    _type = dev
  };

  ChameleonConnectType get connection {
    if (info.usbVendorId == 0x1915) {
      return ChameleonConnectType.dfu;
    }
    return ChameleonConnectType.usb;
  }
}

// Class for WebUSB API Serial Communication
class SerialConnector extends AbstractSerial {
  Map<String, DeviceInfo> deviceMap = {};
  DeviceInfo? currentDevice;

  @override
  // ignore: overridden_fields
  String portName = "WebSerial";

  @override
  get device {
    if (currentDevice != null) {
      return currentDevice!.type;
    }

    return ChameleonDevice.none;
  }

  @override
  set device(ChameleonDevice device) {
    if (currentDevice != null) {
      currentDevice!.type = device;
    }
  }

  @override
  get connectionType {
    if (currentDevice != null) {
      return currentDevice!.connection;
    }

    return ChameleonConnectType.none;
  }

  @override
  Future<void> pairDevices() async {
    try {
      await window.navigator.serial.requestPort();
    } catch (_) {
      // ignore error
    }
  }

  @override
  Future<bool> performDisconnect() async {
    if (currentDevice != null) {
      final readable = currentDevice!.port.readable;

      if (readable.locked) {
        await readable.cancel();
      }

      await currentDevice!.port.close();

      connected = false;
      currentDevice = null;
      return true;
    }

    connected = false; // For debug button
    return false;
  }

  @override
  Future<List> availableDevices() async {
    deviceMap = {};

    List output = [];

    final pairedDevices = await window.navigator.serial.getPorts();
    for (var deviceValue in pairedDevices) {
      SerialPortInfo deviceInfo = deviceValue.getInfo();
      // log.d('deviceInfo ${deviceInfo.hashCode} ${deviceInfo.usbVendorId} ${deviceInfo.usbProductId}');
      if (deviceInfo.usbVendorId == 0x6868 || deviceInfo.usbVendorId == 0x1915) {
        var portId = '${deviceInfo.usbVendorId!.toRadixString(16)}:${deviceInfo.usbProductId!.toRadixString(16)}';

        deviceMap[portId] = DeviceInfo(deviceValue, deviceInfo);
        output.add(portId);
      }
    }

    return output;
  }

  @override
  Future<List> availableChameleons(bool onlyDFU) async {
    List output = [];

    for (var devicePort in await availableDevices()) {
      var device = deviceMap[devicePort];
      ChameleonConnectType connectionType = ChameleonConnectType.usb;

      if (device!.info.usbProductId == 1) { //}"Proxgrind") {
        log.d("Found Chameleon ${device.deviceName}!");

        if (device.info.usbVendorId == 0x1915) {
          connectionType = ChameleonConnectType.dfu;
          log.w("Chameleon is in DFU mode!");
        }
      }

      if (onlyDFU) {
        if (connectionType == ChameleonConnectType.dfu) {
          output.add(
              {'port': devicePort, 'device': device.type, 'type': connectionType});
        }
      } else {
        output.add(
            {'port': devicePort, 'device': device.type, 'type': connectionType});
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecific(devicePort) async {
    await availableDevices();
    connected = false;

    if (deviceMap.containsKey(devicePort)) {
      var deviceValue = deviceMap[devicePort] as DeviceInfo;
      var serialPort = deviceValue.port;

      try {
        await serialPort.open(
          baudRate: 115200,
          dataBits: DataBits.eight,
          stopBits: StopBits.one,
          parity: Parity.none,
        );

        await serialPort.setSignals(
          dataTerminalReady: true, // DTS
          requestToSend: true, // RTS
          // break: false, // Doesnt work
        );
      } catch (e) {
        // ignore already connected/disconnected errors
        var ignoreError = e.toString().contains('already');
        if (!ignoreError) {
          log.d('open port error: $e');
          return false;
        }
      }

      connected = true;
      device = deviceValue.type;
      currentDevice = deviceValue;

      if (currentDevice!.connection == ChameleonConnectType.dfu) {
        log.w("Chameleon is in DFU mode! ${currentDevice!.connection}");
      }

      return connected;
    }
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (!connected) {
      return false;
    }

    try {
      final writer = currentDevice!.port.writable.writer;

      await writer.ready;
      await writer.write(command);
      await writer.close();

      return true;
    } catch (e) {
      log.e('write error: $e');
      rethrow;
    }
  }

  @override
  Future<Uint8List> read(int length) async {
    if (!connected) {
      return Uint8List.fromList([]);
    }

    final reader = currentDevice!.port.readable.reader;

    try {
      var result = await reader.read();
      if (result.done) {
        // reader.cancel() has been called.
        return Uint8List.fromList([]);
      }
      // value is a Uint8Array.
      return result.value;
    } catch (e) {
      log.e('read error: $e', e);
      rethrow;
    } finally {
      reader.releaseLock();
    }
  }
}
