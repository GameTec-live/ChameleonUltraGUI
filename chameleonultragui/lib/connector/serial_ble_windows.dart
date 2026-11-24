import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final Guid _nrfService = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
final Guid _uartRx = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
final Guid _uartTx = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

const List<int> _uartHandshake = [
  0x11, 0xef, 0x03, 0xfb, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00
];

/// Windows BLE connector using the WinRT implementation of flutter_blue_plus.
class WindowsBLESerial extends AbstractSerial {
  final Map<String, Chameleon> chameleonMap = {};

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _stateSubscription;

  bool inSearch = false;
  bool _reconnecting = false;
  DateTime? _lastScanAt;
  List<Chameleon> _lastScanResult = [];

  WindowsBLESerial({required super.log});

  bool _isChameleonName(String name) {
    return name.startsWith('ChameleonUltra') ||
        name.startsWith('ChameleonLite');
  }

  @override
  bool isManualConnectionSupported() {
    return false;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    // BLE DFU is not implemented; USB remains available for flashing.
    if (onlyDFU || connected || inSearch) {
      return [];
    }

    final now = DateTime.now();
    if (_lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(seconds: 8)) {
      return List<Chameleon>.from(_lastScanResult);
    }

    inSearch = true;
    final found = <String, Chameleon>{};
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        var name = result.advertisementData.advName;
        if (name.isEmpty) {
          name = result.device.platformName;
        }
        if (!_isChameleonName(name)) {
          continue;
        }
        final port = result.device.remoteId.str;
        found[port] = Chameleon(
          port: port,
          device: name.startsWith('ChameleonUltra')
              ? ChameleonDevice.ultra
              : ChameleonDevice.lite,
          type: ConnectionType.ble,
          dfu: false,
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      await FlutterBluePlus.stopScan();
    } catch (e) {
      log.e("Windows BLE scan failed: $e");
    } finally {
      await subscription.cancel();
      inSearch = false;
    }

    _lastScanAt = DateTime.now();
    _lastScanResult = found.values.toList();
    for (final entry in found.entries) {
      chameleonMap[entry.key] = entry.value;
    }
    log.d('Found BLE devices: ${_lastScanResult.length}');
    return _lastScanResult;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    final info = chameleonMap[devicePort];
    if (info == null) {
      return false;
    }

    await performDisconnect();
    pendingConnection = true;

    try {
      final bluetoothDevice = BluetoothDevice.fromId(devicePort.toString());
      _device = bluetoothDevice;

      _stateSubscription = bluetoothDevice.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.disconnected && connected) {
          _reconnect(bluetoothDevice);
        }
      });

      await bluetoothDevice.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );

      await _subscribe(bluetoothDevice);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _rx!.write(_uartHandshake, withoutResponse: false);

      connected = true;
      pendingConnection = false;
      portName = devicePort.toString();
      device = info.device;
      activeDevicePort = devicePort;
      connectionType = ConnectionType.ble;
      isDFU = false;
      log.d("Connected to BLE device $devicePort");
      notifyConnectionStateChanged();
      return true;
    } catch (e) {
      log.e("BLE connection failed: $e");
      await performDisconnect();
      return false;
    }
  }

  Future<void> _subscribe(BluetoothDevice bluetoothDevice) async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    _rx = null;
    _tx = null;

    final services = await bluetoothDevice.discoverServices();
    BluetoothService? uart;
    for (final service in services) {
      if (service.uuid == _nrfService) {
        uart = service;
        break;
      }
    }
    if (uart == null) {
      throw "Nordic UART service not found";
    }

    for (final characteristic in uart.characteristics) {
      if (characteristic.uuid == _uartRx) {
        _rx = characteristic;
      } else if (characteristic.uuid == _uartTx) {
        _tx = characteristic;
      }
    }
    if (_rx == null || _tx == null) {
      throw "Nordic UART characteristics not found";
    }

    await _tx!.setNotifyValue(true);
    _valueSubscription = _tx!.onValueReceived.listen((data) {
      if (messageCallback != null) {
        try {
          messageCallback(Uint8List.fromList(data));
        } catch (_) {
          log.w("Received unexpected data: ${bytesToHex(Uint8List.fromList(data))}");
        }
      }
    }, onError: (Object error) {
      log.e(error);
    });
  }

  Future<void> _reconnect(BluetoothDevice bluetoothDevice) async {
    if (_reconnecting) {
      return;
    }
    _reconnecting = true;
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          await bluetoothDevice.connect(
            license: License.nonprofit,
            timeout: const Duration(seconds: 2),
          );
          await _subscribe(bluetoothDevice);
          await _rx!.write(_uartHandshake, withoutResponse: false);
          return;
        } catch (error) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      await performDisconnect();
    } finally {
      _reconnecting = false;
    }
  }

  @override
  Future<bool> performDisconnect() async {
    final hadState = hasConnectionState || _device != null;
    final device = _device;
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    _device = null;
    _rx = null;
    _tx = null;
    resetConnectionState();
    try {
      await device?.disconnect();
    } catch (_) {}
    if (hadState) {
      notifyConnectionStateChanged();
    }
    return hadState;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final rx = _rx;
    if (rx == null) {
      throw "BLE not connected";
    }
    await rx.write(command, withoutResponse: firmware);
    return true;
  }
}
