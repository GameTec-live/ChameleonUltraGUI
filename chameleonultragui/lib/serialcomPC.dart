import 'dart:io';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class CommmodulePC {
  // Class for PC Serial Communication
  SerialPort? port;
  String? device;

  List availableDevices() {
    return SerialPort.availablePorts;
  }

  void connectDevice(String adress) {
    port = SerialPort(adress);
    port!.config.baudRate = 115200;
    port!.config.dtr = 1;
    port!.openReadWrite();
  }

  void sendcommand(String command) {
    print(command);
    print(port);
  }

  List createDataFrame() {
    List dataFrame = [];
    dataFrame.add(0x11);

    return dataFrame;
  }
}

// https://pub.dev/packages/flutter_libserialport/example <- PC Serial Library