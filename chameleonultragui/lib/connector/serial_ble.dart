import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

Uuid _UART_UUID = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid _UART_RX = Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid _UART_TX = Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

class BLESerial extends AbstractSerial {
  FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  QualifiedCharacteristic? txCharacteristic;
  QualifiedCharacteristic? rxCharacteristic;
  Stream<List<int>>? receivedDataStream;
  StreamSubscription<ConnectionStateUpdate>? connection;
  List<Uint8List> messagePool = [];

  @override
  Future<List> availableDevices() async {
    List<DiscoveredDevice> foundDevices = [];
    await preformDisconnect();

    StreamSubscription<DiscoveredDevice> subscription;

    subscription = flutterReactiveBle.scanForDevices(
      withServices: [_UART_UUID],
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
    if (onlyDFU) {
      throw ("DFU not supported via BLE");
    }

    List output = [];
    for (var bleDevice in await availableDevices()) {
      if (bleDevice.name.startsWith('ChameleonUltra')) {
        device = ChameleonDevice.ultra;
      } else if (bleDevice.name.startsWith('ChameleonLite')) {
        device = ChameleonDevice.lite;
      } else {
        continue;
      }

      connectionType = ChameleonConnectType.ble;

      log.d(
          "Found Chameleon ${device == ChameleonDevice.ultra ? 'Ultra' : 'Lite'}!");

      output.add(
          {'port': bleDevice.id, 'device': device, 'type': connectionType});
    }

    return output;
  }

  @override
  Future<bool> connectSpecific(deviceName) async {
    Completer<bool> completer = Completer<bool>();

    await preformDisconnect();
    connection = flutterReactiveBle
        .connectToAdvertisingDevice(
      id: deviceName,
      withServices: [_UART_UUID, _UART_RX, _UART_TX],
      prescanDuration: const Duration(seconds: 5),
    )
        .listen((connectionState) async {
      log.w(connectionState);
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        connected = true;

        txCharacteristic = QualifiedCharacteristic(
            serviceId: _UART_UUID,
            characteristicId: _UART_TX,
            deviceId: connectionState.deviceId);
        receivedDataStream =
            flutterReactiveBle.subscribeToCharacteristic(txCharacteristic!);
        receivedDataStream!.listen((data) {
          messagePool.add(Uint8List.fromList(data));
        }, onError: (dynamic error) {
          log.e(error);
        });

        rxCharacteristic = QualifiedCharacteristic(
            serviceId: _UART_UUID,
            characteristicId: _UART_RX,
            deviceId: connectionState.deviceId);

        portName = deviceName;
        device = ChameleonDevice.ultra;
        connectionType = ChameleonConnectType.ble;
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
  Future<bool> write(Uint8List command) async {
    await flutterReactiveBle.writeCharacteristicWithResponse(rxCharacteristic!,
        value: command);
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
