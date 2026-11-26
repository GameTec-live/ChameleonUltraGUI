import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_native.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _Port extends Fake implements SerialPort {
  @override
  final int transport;
  @override
  final int? vendorId;
  @override
  final int? productId;
  @override
  final String? productName;
  @override
  final String? manufacturer;
  @override
  final String? description;
  bool disposed = false;

  _Port({
    this.transport = SerialPortTransport.usb,
    this.vendorId,
    this.productId,
    this.productName,
    this.manufacturer,
    this.description,
  });

  @override
  void dispose() => disposed = true;
}

class _Serial extends NativeSerial {
  final Map<String, _Port> ports;
  _Serial(this.ports) : super(log: Logger());

  @override
  Future<List<String>> availableDevices() async => ports.keys.toList();

  @override
  SerialPort serialPort(String address) => ports[address]!;
}

void main() {
  test('scan skips offline Bluetooth ports and reads USB metadata', () async {
    final ports = {
      'COM10': _Port(transport: SerialPortTransport.bluetooth),
      'COM7': _Port(
        vendorId: 0x6868,
        productId: 0x8686,
        description: 'USB 串行设备 (COM7)',
      ),
      'COM8': _Port(vendorId: 0x6868, productId: 0x1234),
      'COM9': _Port(productName: 'ChameleonLite'),
    };
    final serial = _Serial(ports);
    // Fake throws if discovery calls openReadWrite() or configures a port.
    final found = await serial.availableChameleons(false);
    expect(found.map((item) => item.port), ['COM7', 'COM9']);
    expect(found.last.device, ChameleonDevice.lite);
    expect(ports.values.every((port) => port.disposed), isTrue);
    expect(serial.connected, isFalse);
  });

  test('DFU scan excludes normal devices and unrelated bootloaders', () async {
    final serial = _Serial({
      'COM4': _Port(vendorId: 0x1915, productId: 0x521f),
      'COM5': _Port(
        vendorId: 0x1915,
        productId: 0x521f,
        productName: 'ChameleonUltra DFU',
      ),
      'COM6': _Port(vendorId: 0x6868, productId: 0x8686),
    });
    final found = await serial.availableChameleons(true);
    expect(found.single.port, 'COM5');
    expect(found.single.device, ChameleonDevice.ultra);
    expect(found.single.dfu, isTrue);
  });
}
