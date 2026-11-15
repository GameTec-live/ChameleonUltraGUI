import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/mifare_classic/gen4.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:logger/logger.dart';

/// In-memory card at the raw RF boundary; used for protocol/UI exercises.
class Gen4TestDevice extends ChameleonCommunicator {
  Gen4TestDevice() : super(Logger());
  Uint8List config = gen4ParseHex(
    '00000000000002000978009102DABC191010111213141516040008006B02',
  );
  final commands = <Uint8List>[];
  bool reader = false;
  bool rejectWrite = false;
  Uint8List version = gen4ParseHex('00000006A0');

  @override
  Future<bool> isReaderDeviceMode() async => reader;
  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {
    reader = readerMode;
  }

  @override
  Future<Uint8List> send14ARaw(
    Uint8List data, {
    int respTimeoutMs = 100,
    int? bitLen,
    bool activateRfField = true,
    bool waitResponse = true,
    bool appendCrc = true,
    bool autoSelect = true,
    bool keepRfField = false,
    bool checkResponseCrc = true,
  }) async {
    if (checkResponseCrc || respTimeoutMs != 1000 || !autoSelect) {
      throw StateError('Unexpected RF flags');
    }
    commands.add(data);
    if (gen4Hex(data.sublist(1, 5)) != gen4Hex(config.sublist(2, 6))) {
      return gen4ParseHex('6300');
    }
    switch (data[5]) {
      case 0xC6:
        return Uint8List.fromList(config);
      case 0xCC:
        return version;
      case 0xF0:
      case 0xF1:
        if (rejectWrite) return gen4ParseHex('6300');
        config = data.sublist(6);
        return gen4ParseHex('9000FD07');
      case 0xCE:
        return Uint8List(16);
      case 0xCD:
        return gen4ParseHex('9000');
      default:
        throw StateError('Unexpected command');
    }
  }
}

ChameleonGUIState gen4TestState(Gen4TestDevice device) =>
    ChameleonGUIState(SharedPreferencesProvider())
      ..connector = _Serial()
      ..communicator = device;

class _Serial extends AbstractSerial {
  _Serial() : super(log: Logger()) {
    connected = true;
    device = ChameleonDevice.ultra;
  }
  @override
  bool isManualConnectionSupported() => false;
  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;
  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];
  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;
}
