import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:universal_ble/universal_ble.dart';

const nrfUUID = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
const uartRX = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
const uartTX = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

const dfuUUID = 'FE59';
const dfuControl = '8EC90001-F315-4F60-9FB8-838830DAEA50';
const dfuFirmware = '8EC90002-F315-4F60-9FB8-838830DAEA50';

class BLESerial extends AbstractSerial {
  BleCharacteristic? txCharacteristic;
  BleCharacteristic? rxCharacteristic;
  BleCharacteristic? firmwareCharacteristic;
  StreamSubscription<Uint8List>? receivedDataSubscription;
  StreamSubscription<bool>? connectionSubscription;
  final Map<String, Chameleon> chameleonMap = {};
  final Map<String, BleDevice> bleDevices = {};
  bool inSearch = false;

  BLESerial({required super.log});

  Future<List<BleDevice>> availableDevices() async {
    if (inSearch) {
      log.w('Multiple searches at the same time are not allowed');
      return [];
    }

    await performDisconnect();
    final foundDevices = <String, BleDevice>{};
    inSearch = true;
    final subscription = UniversalBle.scanStream.listen(
      (device) => foundDevices[device.deviceId] = device,
      onError: (Object error) => log.e('Got BLE search error: $error'),
    );

    try {
      await UniversalBle.startScan();
      await Future<void>.delayed(const Duration(seconds: 2));
      await UniversalBle.stopScan();
      log.d('Found BLE devices: ${foundDevices.length}');
      return foundDevices.values.toList();
    } catch (error) {
      log.e('Got BLE search error: $error');
      return [];
    } finally {
      await subscription.cancel();
      inSearch = false;
    }
  }

  @override
  bool isManualConnectionSupported() => false;

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    final output = <Chameleon>[];
    chameleonMap.clear();
    bleDevices.clear();
    for (final bleDevice in await availableDevices()) {
      final name = bleDevice.name ?? '';
      var dfuMode = false;
      ChameleonDevice foundDevice;
      if (name.startsWith('ChameleonUltra')) {
        foundDevice = ChameleonDevice.ultra;
      } else if (name.startsWith('ChameleonLite')) {
        foundDevice = ChameleonDevice.lite;
      } else if (name.startsWith('CU-')) {
        foundDevice = ChameleonDevice.ultra;
        dfuMode = true;
      } else if (name.startsWith('CL-')) {
        foundDevice = ChameleonDevice.lite;
        dfuMode = true;
      } else {
        continue;
      }

      final chameleon = Chameleon(
        port: bleDevice.deviceId,
        device: foundDevice,
        type: ConnectionType.ble,
        dfu: dfuMode,
      );
      chameleonMap[bleDevice.deviceId] = chameleon;
      bleDevices[bleDevice.deviceId] = bleDevice;
      if (!onlyDFU || dfuMode) output.add(chameleon);
      log.d('Found Chameleon ${chameleonDeviceName(foundDevice)} over BLE');
    }
    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (await _connectSpecificInternal(devicePort as String)) return true;
    }
    return false;
  }

  Future<bool> _connectSpecificInternal(String deviceId) async {
    final chameleon = chameleonMap[deviceId];
    final bleDevice = bleDevices[deviceId];
    if (chameleon == null || bleDevice == null) return false;

    await performDisconnect();
    pendingConnection = true;
    try {
      await bleDevice.connect(timeout: const Duration(seconds: 10));
      connectionSubscription =
          bleDevice.connectionStream.listen((isConnected) async {
        if (!isConnected && connected) await performDisconnect();
      });
      await bleDevice.discoverServices(timeout: const Duration(seconds: 10));

      final service = chameleon.dfu ? dfuUUID : nrfUUID;
      final tx = chameleon.dfu ? dfuControl : uartTX;
      final rx = chameleon.dfu ? dfuControl : uartRX;
      txCharacteristic =
          await bleDevice.getCharacteristic(tx, service: service);
      rxCharacteristic =
          await bleDevice.getCharacteristic(rx, service: service);
      if (chameleon.dfu) {
        firmwareCharacteristic = await bleDevice.getCharacteristic(
          dfuFirmware,
          service: dfuUUID,
        );
      }

      receivedDataSubscription = txCharacteristic!.onValueReceived.listen(
        _handleReceivedData,
        onError: (Object error) async {
          log.e(error);
          await performDisconnect();
        },
      );
      await txCharacteristic!.notifications.subscribe();

      if (!chameleon.dfu) {
        await rxCharacteristic!.write(<int>[
          0x11,
          0xef,
          0x03,
          0xfb,
          0x00,
          0x00,
          0x00,
          0x00,
          0x02,
          0x00,
        ]);
      }

      connected = true;
      pendingConnection = false;
      portName = deviceId;
      activeDevicePort = deviceId;
      device = chameleon.device;
      connectionType = ConnectionType.ble;
      isDFU = chameleon.dfu;
      return true;
    } catch (error) {
      log.e('BLE connection to $deviceId failed: $error');
      await performDisconnect();
      return false;
    }
  }

  Future<void> _handleReceivedData(Uint8List data) async {
    if (messageCallback == null) return;
    try {
      await messageCallback(data);
    } catch (_) {
      log.w('Received unexpected data: ${bytesToHex(data)}');
    }
  }

  @override
  Future<bool> performDisconnect() async {
    final hadState = hasConnectionState || activeDevicePort != null;
    final deviceId = activeDevicePort as String?;
    resetConnectionState();
    await receivedDataSubscription?.cancel();
    receivedDataSubscription = null;
    await connectionSubscription?.cancel();
    connectionSubscription = null;
    txCharacteristic = null;
    rxCharacteristic = null;
    firmwareCharacteristic = null;
    if (deviceId != null) await UniversalBle.disconnect(deviceId);
    connected = false;
    if (hadState) notifyConnectionStateChanged();
    return deviceId != null;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    final characteristic = firmware ? firmwareCharacteristic : rxCharacteristic;
    if (characteristic == null) return false;
    await characteristic.write(command, withResponse: !firmware);
    return true;
  }
}
