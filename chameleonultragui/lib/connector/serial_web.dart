import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'package:serial/serial.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';

class SerialAdapter extends AbstractSerial {
  @override
  // ignore: overridden_fields
  String name = "Web";

  SerialPort? port;
  web.ReadableStreamDefaultReader? reader;
  bool _keepReading = true;

  SerialAdapter({required super.log});

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    return [];
  }

  @override
  Future<bool> connectSpecificDevice(devicePort) async {
    try {
      port = await web.window.navigator.serial.requestPort().toDart;

      await port!
          .open(
            baudRate: 115200,
            dataBits: DataBits.eight,
            stopBits: StopBits.one,
            parity: Parity.none,
            flowControl: FlowControl.hardware,
          )
          .toDart;

      final info = port!.getInfo();
      isDFU = info.usbVendorId == 0x1915;

      portName = "Web Serial";
      connected = true;
      connectionType = ConnectionType.usb;
      device = ChameleonDevice.none;

      _keepReading = true;
      _startReceiving();

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _startReceiving() async {
    while (port?.readable != null && _keepReading) {
      reader = port!.readable!.getReader() as web.ReadableStreamDefaultReader;

      while (_keepReading) {
        try {
          final result = await reader!.read().toDart;

          if (result.done) {
            break;
          }

          final value = result.value;
          if (value != null && value.isA<JSUint8Array>()) {
            final data = value as JSUint8Array;
            final uint8Data = data.toDart;

            if (messageCallback != null) {
              messageCallback(uint8Data);
            }
          }
        } catch (e) {
          log.e(e);
          await performDisconnect();
          return;
        }
      }

      reader?.releaseLock();
    }
  }

  @override
  Future<bool> performDisconnect() async {
    _keepReading = false;

    if (reader != null) {
      try {
        await reader!.cancel().toDart;
      } catch (_) {}

      reader = null;
    }

    if (port != null) {
      try {
        await port!.close().toDart;
      } catch (_) {}

      port = null;
    }

    connected = false;
    isOpen = false;
    connectionType = ConnectionType.none;
    device = ChameleonDevice.none;

    return true;
  }

  @override
  bool isManualConnectionSupported() {
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final writer = port?.writable?.getWriter();
    if (writer != null) {
      await writer.write(command.toJS).toDart;
      writer.releaseLock();
      return true;
    }

    return false;
  }
}
