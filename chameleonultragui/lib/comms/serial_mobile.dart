import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';

class MobileSerial extends AbstractSerial {
  @override
  bool async = true;
  // Class for Android Serial Communication
  @override
  List availableChameleons() {
    return [];
  }
}
