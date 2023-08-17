import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// Regular
Uuid nrfUUID = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartRX = Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartTX = Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

// DFU
Uuid dfuUUID = Uuid.parse("FE59");
Uuid dfuControl = Uuid.parse("8EC90001-F315-4F60-9FB8-838830DAEA50");
Uuid dfuFirmware = Uuid.parse("8EC90002-F315-4F60-9FB8-838830DAEA50");

class BLESerial extends AbstractSerial {
  FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  QualifiedCharacteristic? txCharacteristic;
  QualifiedCharacteristic? rxCharacteristic;
  QualifiedCharacteristic? firmwareCharacteristic;
  Stream<List<int>>? receivedDataStream;
  StreamSubscription<ConnectionStateUpdate>? connection;
  List<Uint8List> messagePool = [];
  Map<String, Map> chameleonMap = {};

  @override
  Future<List> availableDevices() async {
    List<DiscoveredDevice> foundDevices = [];
    await preformDisconnect();

    StreamSubscription<DiscoveredDevice> subscription;

    subscription = flutterReactiveBle.scanForDevices(
      withServices: [nrfUUID, dfuUUID],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (!foundDevices.contains(device)) {
        for (var foundDevice in foundDevices) {
          if (foundDevice.id == device.id) {
            return;
          }
        }
        foundDevices.add(device);
      }
    });

    Completer<List<DiscoveredDevice>> completer =
        Completer<List<DiscoveredDevice>>();

    Timer(const Duration(seconds: 2), () {
      subscription.cancel();
      log.d('Found BLE devices: ${foundDevices.length}');
      completer.complete(foundDevices);
    });

    return completer.future;
  }

  @override
  Future<List> availableChameleons(bool onlyDFU) async {
    List output = [];
    for (var bleDevice in await availableDevices()) {
      if (bleDevice.name.startsWith('ChameleonUltra')) {
        device = ChameleonDevice.ultra;
      } else if (bleDevice.name.startsWith('ChameleonLite')) {
        device = ChameleonDevice.lite;
      } else if (bleDevice.name.startsWith('CU-')) {
        device = ChameleonDevice.ultra;
      }

      connectionType = ChameleonConnectType.ble;
      if (bleDevice.name.startsWith('CU-')) {
        connectionType = ChameleonConnectType.dfu;
      }

      log.d(
          "Found Chameleon ${device == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}!");
      if (!onlyDFU || onlyDFU && connectionType == ChameleonConnectType.dfu) {
        output.add(
            {'port': bleDevice.id, 'device': device, 'type': connectionType});
      }

      chameleonMap[bleDevice.id] = {
        'port': bleDevice.id,
        'device': device,
        'type': connectionType
      };
    }

    return output;
  }

  @override
  Future<bool> connectSpecific(devicePort) async {
    // As BLE is unstable, we try to connect 5 times
    // And fail only then
    bool ret = false;
    for (var i = 0; i < 5; i++) {
      ret = await connectSpecificInternal(devicePort);
      if (ret) {
        break;
      }
    }

    return ret;
  }

  Future<bool> connectSpecificInternal(devicePort) async {
    Completer<bool> completer = Completer<bool>();
    List<Uuid> services = [nrfUUID, uartRX, uartTX];
    if (chameleonMap[devicePort]!['type'] == ChameleonConnectType.dfu) {
      services = [dfuUUID, dfuControl, dfuFirmware];
    }

    await preformDisconnect();
    connection = flutterReactiveBle
        .connectToAdvertisingDevice(
      id: devicePort,
      withServices: services,
      prescanDuration: const Duration(seconds: 5),
    )
        .listen((connectionState) async {
      log.w(connectionState);
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        connected = true;

        if (chameleonMap[devicePort]!['type'] == ChameleonConnectType.dfu) {
          txCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuControl,
              deviceId: connectionState.deviceId);
          receivedDataStream =
              flutterReactiveBle.subscribeToCharacteristic(txCharacteristic!);
          receivedDataStream!.listen((data) {
            messagePool.add(Uint8List.fromList(data));
          }, onError: (dynamic error) {
            log.e(error);
          });

          rxCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuControl,
              deviceId: connectionState.deviceId);

          firmwareCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuFirmware,
              deviceId: connectionState.deviceId);

          portName = devicePort;
          device = chameleonMap[devicePort]!['device'];

          connectionType = ChameleonConnectType.dfu;
        } else {
          txCharacteristic = QualifiedCharacteristic(
              serviceId: nrfUUID,
              characteristicId: uartTX,
              deviceId: connectionState.deviceId);
          receivedDataStream =
              flutterReactiveBle.subscribeToCharacteristic(txCharacteristic!);
          receivedDataStream!.listen((data) {
            messagePool.add(Uint8List.fromList(data));
          }, onError: (dynamic error) {
            log.e(error);
          });

          rxCharacteristic = QualifiedCharacteristic(
              serviceId: nrfUUID,
              characteristicId: uartRX,
              deviceId: connectionState.deviceId);

          portName = devicePort;
          device = chameleonMap[devicePort]!['device'];

          connectionType = ChameleonConnectType.ble;
        }

        completer.complete(true);
      } else if (connectionState.connectionState ==
          DeviceConnectionState.disconnected) {
        completer.complete(false);
      }
    }, onError: (Object error) {
      log.e(error);
      completer.complete(false);
    });

    return completer.future;
  }

  @override
  Future<bool> preformDisconnect() async {
    device = ChameleonDevice.none;
    connectionType = ChameleonConnectType.none;
    if (connection != null) {
      await connection!.cancel();
      connected = false;
      return true;
    }
    connected = false; // For debug button
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (firmware) {
      await flutterReactiveBle.writeCharacteristicWithoutResponse(
          firmwareCharacteristic!,
          value: command);
    } else {
      await flutterReactiveBle
          .writeCharacteristicWithResponse(rxCharacteristic!, value: command);
    }

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
      await asyncSleep(10);
    }

    return completer.future;
  }
}
