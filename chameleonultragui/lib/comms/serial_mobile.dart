import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';

class MobileSerial extends AbstractSerial {
  // Class for Android Serial Communication
  @override
  Future<List> availableChameleons() async {
    return [];
  }
}
