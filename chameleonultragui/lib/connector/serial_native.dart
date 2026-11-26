import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_abstract.dart';

class NativeSerial extends AbstractSerial {
  // Class for PC Serial Communication
  SerialPort? port;
  SerialPortReader? reader;

  NativeSerial({required super.log});

  @override
  bool isManualConnectionSupported() {
    return true;
  }

  Future<List<String>> availableDevices() async => SerialPort.availablePorts;

  SerialPort serialPort(String address) => SerialPort(address);

  @override
  Future<bool> performConnect() async {
    for (final candidate in await availableChameleons(false)) {
      if (await connectSpecificDevice(candidate.port)) return true;
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
    final output = <Chameleon>[];
    for (final address in await availableDevices()) {
      SerialPort? candidate;
      try {
        candidate = serialPort(address);
        final info = _identify(candidate, address);
        if (info != null && (!onlyDFU || info.dfu)) output.add(info);
      } on SerialPortError catch (e) {
        log.d("Skipping $address: $e");
      } finally {
        candidate?.dispose();
      }
    }
    return output;
  }

  Chameleon? _identify(SerialPort candidate, String address,
      {bool manual = false}) {
    int? vid;
    int? pid;
    if (candidate.transport == SerialPortTransport.usb) {
      try {
        vid = candidate.vendorId;
        pid = candidate.productId;
      } on SerialPortError catch (e) {
        // Some drivers expose a device name without a USB ID.
        log.d("USB IDs unavailable for $address: $e");
      }
    }

    final name = '${candidate.productName ?? ''} ${candidate.description ?? ''}'
        .toLowerCase();
    final named = candidate.manufacturer?.toLowerCase() == 'proxgrind' ||
        name.contains('chameleon');
    final knownId = vid == 0x6868 && pid == 0x8686;
    // Nordic's DFU ID is shared with other products.
    if (!knownId && !named && !manual) return null;

    final ultra = name.contains('ultra') || (!named && !name.contains('lite'));
    return Chameleon(
        port: address,
        device: ultra ? ChameleonDevice.ultra : ChameleonDevice.lite,
        type: ConnectionType.usb,
        dfu: vid == 0x1915 && (pid == 0x521f || (pid == null && named)));
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    if (connected) return activeDevicePort == devicePort;
    SerialPort? candidate;
    var opened = false;
    try {
      candidate = serialPort(devicePort);
      final info = _identify(candidate, devicePort, manual: true)!;
      opened = candidate.openReadWrite();
      if (!opened) {
        log.e("Could not open $devicePort: ${SerialPort.lastError}");
        return false;
      }
      candidate.config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..rts = SerialPortRts.flowControl
        ..cts = SerialPortCts.flowControl
        ..dsr = SerialPortDsr.flowControl
        ..dtr = SerialPortDtr.flowControl
        ..setFlowControl(SerialPortFlowControl.rtsCts);

      port = candidate;
      device = info.device;
      isDFU = info.dfu;
      connectionType = info.type;
      portName = devicePort;
      activeDevicePort = devicePort;
      connected = true;
      return true;
    } on SerialPortError catch (e) {
      log.e(e);
      return false;
    } finally {
      if (candidate != null && !identical(candidate, port)) {
        if (opened) candidate.close();
        candidate.dispose();
      }
    }
  }

  @override
  Future<void> open() async {
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
