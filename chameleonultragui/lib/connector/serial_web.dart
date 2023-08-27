import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:serial/serial.dart';

class SerialPortDeviceWeb {
  final SerialPort port;
  final SerialPortInfo info;
  ChameleonDevice _type = ChameleonDevice.unknown;
  SerialPortDeviceWeb(this.port, this.info);

  ChameleonDevice get type {
    return _type;
  }

  set type(ChameleonDevice dev) => {
    _type = dev
  };

  ConnectionType get connection {
    return ConnectionType.usb;
  }
}

// Class for WebUSB API Serial Communication
class SerialConnector extends AbstractSerial {
  Map<String, SerialPortDeviceWeb> deviceMap = {};
  SerialPortDeviceWeb? currentDevice;
  ReadableStreamReader? reader;
  WritableStreamDefaultWriter? writer;

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

    return ConnectionType.none;
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
    super.performDisconnect();
    connected = false;

    try {
      await reader!.cancel();
      reader!.releaseLock();
    } catch (error) {
      log.d('performDisconnect:reader', error: error);
    }

    try {
      writer!.releaseLock();
    } catch (error) {
      log.d('performDisconnect:writer', error: error);
    }

    await currentDevice!.port.close();

    reader = null;
    writer = null;

    currentDevice = null;
    messageCallback = null;
    return true;
  }

  @override
  Future<List> availableDevices() async {
    deviceMap = {};

    List output = [];

    final pairedDevices = await window.navigator.serial.getPorts();

    pairedDevices.asMap().forEach((index, port) {
      SerialPortInfo deviceInfo = port.getInfo();

      if (isChameleonVendor(deviceInfo.usbVendorId)) {
        var portId = '${deviceInfo.usbVendorId!.toRadixString(16)}:${deviceInfo.usbProductId!.toRadixString(16)}:$index';

        deviceMap[portId] = SerialPortDeviceWeb(port, deviceInfo);
        output.add(portId);
      }
    });

    return output;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];

    for (var devicePort in await availableDevices()) {
      var device = deviceMap[devicePort];
      if (device == null) {
        continue;
      }

      if (isChameleonVendor(device.info.usbVendorId, ChameleonVendor.dfu)) {
        log.w("Chameleon is in DFU mode!");

        output.add(Chameleon(
            port: devicePort,
            device: device.type,
            type: ConnectionType.usb,
            dfu: true))
        ;
      } else if (isChameleonVendor(device.info.usbVendorId, ChameleonVendor.proxgrind)) {
        log.d("Found ${device.type.name}!");

        if (!onlyDFU) {
          output.add(Chameleon(
              port: devicePort,
              device: device.type,
              type: ConnectionType.usb,
              dfu: false)
          );
        }
      }
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(devicePort) async {
    await availableDevices();
    connected = false;

    var serialDevice = deviceMap[devicePort];
    if (serialDevice == null) {
      log.d('Port $devicePort not found in device map');
      return false;
    }
  
    var port = serialDevice.port;

    try {
      await port.open(
        baudRate: 115200,
        dataBits: DataBits.eight,
        stopBits: StopBits.one,
        parity: Parity.none,
        bufferSize: 255,
        flowControl: FlowControl.none,
      );

      await port.setSignals(
        dataTerminalReady: true, // DTS
        requestToSend: true, // RTS
        // break: false, // Doesnt work but is default
      );
    } catch (e) {
      // ignore already connected/disconnected errors
      var ignoreError = false; //e.toString().contains('already');
      if (!ignoreError) {
        log.d('Open port error: $e');
        return false;
      }
    }

    connected = true;
    device = serialDevice.type;
    currentDevice = serialDevice;
    isDFU = serialDevice.info.usbVendorId == ChameleonVendor.dfu.value;

    if (isDFU) {
      log.w("Chameleon is in DFU mode! ${currentDevice!.connection}");
    }

    listen();

    return connected;
  }

  Future<void> listen() async {
    // log.d('Read listener starting: $connected');

    while(connected) { // main read loop
      // Dont catch error if we cannot get a reader
      reader = currentDevice!.port.readable.reader;

      try {
        // Block the while loop until there is more data to read on the stream
        // Dont use a timeout here, cause then the app is running the loop
        // all the time causing high(er) cpu usage
        final result = await reader!.read();
        if (result.done) {
          break;
        }

        messageCallback!(result.value);
      } catch (error) {
        log.e('Read error $error', error: error);

        if (error.toString().contains('The device has been lost')) {
          performDisconnect();
        }
      } finally {
        reader!.releaseLock();
      }
    }

    // log.d('Read listener stopped');
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (!connected) {
      return false;
    }

    try {
      writer = currentDevice!.port.writable.writer;

      await writer!.ready;
      await writer!.write(command);
      writer!.releaseLock();

      return true;
    } catch (e) {
      log.e('Write error: $e');
      rethrow;
    }
  }
}
