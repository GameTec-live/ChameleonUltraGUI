import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLESerial extends AbstractSerial {
  Future<List> availableDevicesBLE() async {
    List<BluetoothDevice> devices = [];

    // Start scanning for BLE devices
    FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4), androidUsesFineLocation: false);

    // Wait for scan to complete
    await Future.delayed(const Duration(seconds: 4));

    // Get a list of discovered devices
    List<ScanResult> scanResults = await FlutterBluePlus.stopScan();

    // Add each discovered device to the list
    for (ScanResult result in scanResults) {
      devices.add(result.device);
    }

    return devices;
  }

  Future<bool> connectDevice(BluetoothDevice device) async {
    await device.connect();
    return true;
  }
}
// https://pub.dev/packages/flutter_blue_plus