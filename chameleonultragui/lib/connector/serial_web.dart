import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:serial/serial.dart';

class DeviceInfo {
  final SerialPort port;
  final SerialPortInfo info;
  final ChameleonConnectType connection = ChameleonConnectType.usb;
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
}

// Class for WebUSB API Serial Communication
class SerialConnector extends AbstractSerial {
  Map<String, DeviceInfo> deviceMap = {};
  List<Uint8List> messagePool = []; // TODO: Fix or rewrite on release
  DeviceInfo? currentDevice;

  ReadableStreamReader? reader;
  bool keepReading = false;

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
    device = ChameleonDevice.none;
    connectionType = ChameleonConnectType.none;
    if (currentDevice != null) {
      final readable = currentDevice!.port.readable;

      if (readable.locked) {
        if (reader != null) {
          await reader!.cancel();
          reader = null;
        }

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
    device = ChameleonDevice.none;
    connectionType = ChameleonConnectType.none;
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

      listen();

      if (deviceValue.info.usbVendorId == 0x1915) {
        connectionType = ChameleonConnectType.dfu;
        log.w("Chameleon is in DFU mode!");
      } else {
        connectionType = ChameleonConnectType.usb;
      }

      return connected;
    }
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    try {
      final writer = currentDevice!.port.writable.writer;

      await writer.ready;
      await writer.write(command);
      await writer.close();

      return true;
    } catch (e) {
      log.e('write error: $e');
    }

    return false;
  }

  Future listen () async {
    final readable = currentDevice!.port.readable;
    if (!readable.locked && reader == null) {
      reader = currentDevice!.port.readable.reader;
    }

    keepReading = true;

    while (connected && keepReading) {
      try {
        var result = await reader!.read();
        if (result.done) {
          keepReading = false;
          // reader.cancel() has been called.
          break;
        }
        // value is a Uint8Array.
        messagePool.add(result.value);
      } catch (e) {
        log.e('read error: $e', e);
        keepReading = false;
      }
    }

    // Allow the serial port to be closed later.
    reader!.releaseLock();
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

  @override
  Future<void> finishRead() async {
    messagePool = [];
  }
}
