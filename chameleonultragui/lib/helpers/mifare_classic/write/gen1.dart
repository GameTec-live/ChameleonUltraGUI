import 'dart:typed_data';

import 'package:chameleonultragui/helpers/mifare_classic/write/base.dart';

class MifareClassicGen1WriteHelper extends BaseMifareClassicMagicCardHelper {
  MifareClassicGen1WriteHelper(super.communicator, {required super.recovery});

  @override
  String get name => "Gen1";

  static String get staticName => "Gen1";

  @override
  Future<bool> isMagic(dynamic data) async {
    await communicator.send14ARaw(Uint8List(1)); // reset

    Uint8List data = await communicator.send14ARaw(Uint8List.fromList([0x40]),
        bitLen: 7,
        appendCrc: false,
        autoSelect: false,
        checkResponseCrc: false,
        keepRfField: true);

    if (data.isNotEmpty && data[0] == 0x0a) {
      data = await communicator.send14ARaw(Uint8List.fromList([0x43]),
          appendCrc: false,
          autoSelect: false,
          checkResponseCrc: false,
          keepRfField: true);
      return data.isNotEmpty && data[0] == 0x0a;
    }

    return false;
  }

  @override
  bool isReady() {
    return true;
  }

  @override
  Future<bool> writeBlock(int block, Uint8List data) async {
    await communicator.send14ARaw(Uint8List(1)); // reset

    await communicator.send14ARaw(Uint8List.fromList([0x40]),
        bitLen: 7,
        appendCrc: false,
        autoSelect: false,
        checkResponseCrc: false,
        keepRfField: true);

    await communicator.send14ARaw(Uint8List.fromList([0x43]),
        appendCrc: false,
        autoSelect: false,
        checkResponseCrc: false,
        keepRfField: true);

    await communicator.send14ARaw(Uint8List.fromList([0xA0, block]),
        autoSelect: false, keepRfField: true, checkResponseCrc: false);

    Uint8List output = await communicator.send14ARaw(data,
        autoSelect: false, keepRfField: true, checkResponseCrc: false);

    return output.isNotEmpty && output[0] == 0x0a;
  }
}
