import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';

class SerialAdapter extends AbstractSerial {
  @override
  // ignore: overridden_fields
  String name = "Stub";

  SerialAdapter({required super.log});

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) {
    throw UnimplementedError();
  }

  @override
  Future<bool> connectSpecificDevice(devicePort) {
    throw UnimplementedError();
  }

  @override
  bool isManualConnectionSupported() {
    throw UnimplementedError();
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) {
    throw UnimplementedError();
  }
}
