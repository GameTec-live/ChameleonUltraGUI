import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

/// Records each frame and echoes it back so the command completes.
class RecordingSerial extends EmulatorSerial {
  RecordingSerial() : super(log: Logger(level: Level.off)) {
    connected = true;
    device = ChameleonDevice.ultra;
  }

  final frames = <Uint8List>[];

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    frames.add(command);
    final response = Uint8List.fromList(command);
    response[8] = (-(response.sublist(2, 8).fold(0, (a, b) => a + b))) & 255;
    response[response.length - 1] =
        (-(response.sublist(0, response.length - 1).fold(0, (a, b) => a + b))) &
        255;
    await messageCallback(response);
    return true;
  }
}

/// The name bytes setSlotTagName sends: the frame's data without slot and frequency.
Future<List<int>> sentName(String name) async {
  final serial = RecordingSerial();
  await ChameleonCommunicator(
    serial.log,
    port: serial,
  ).setSlotTagName(3, name, TagFrequency.hf);
  final data = serial.frames.single.sublist(9, serial.frames.single.length - 1);
  expect(data.sublist(0, 2), [3, TagFrequency.hf.value]);
  return data.sublist(2);
}

void main() {
  test('slot names within 32 bytes are sent unchanged', () async {
    expect(utf8.decode(await sentName('Office door')), 'Office door');
    final name = 'a' * 32;
    expect(utf8.decode(await sentName(name)), name);
  });

  test('slot names over 32 bytes are cut to 32 bytes without splitting a character', () async {
    // 17 accented letters pass the 19 character check but are 34 bytes.
    expect(utf8.decode(await sentName('é' * 17)), 'é' * 16);
    expect(utf8.decode(await sentName('${'a' * 31}漢')), 'a' * 31);
    expect(utf8.decode(await sentName('${'a' * 30}🔑')), 'a' * 30);
    expect(utf8.decode(await sentName('a' * 40)), 'a' * 32);
  });
}
