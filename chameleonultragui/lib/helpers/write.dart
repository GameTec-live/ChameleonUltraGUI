import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/base.dart';
import 'package:chameleonultragui/main.dart';

abstract class AbstractWriteHelper {
  final ChameleonCommunicator communicator;
  AbstractWriteHelper(this.communicator);

  bool readSupported = false; // can read data without authorization
  bool writeSupported = false; // can write data without authorization

  String get name => "Abstract"; // name in dropdown

  bool get autoDetect => false; // is autodetect supported

  Future<bool> isMagic(dynamic data); // is current card is magic card

  bool isReady(); // card ready to be written

  List<AbstractWriteHelper>
      getAvailableMethods(); // get available methods for automatic check with priority

  Future<void> getCardType(); // get required data from card

  List<dynamic> getExtraData(); // if you want to get data from specific helpers

  Future<void> reset(); // delete data from helper

  static AbstractWriteHelper? getClassByCardType(
      TagType type, ChameleonGUIState appState, void Function() update) {
    if (chameleonTagTypeGetMfClassicType(type) != MifareClassicType.none) {
      return BaseMifareClassicMagicCardHelper(appState.communicator!,
          recovery: MifareClassicRecovery(appState: appState, update: update));
    }

    return null; // writing is not supported
  }

  Future<bool> writeData(List<Uint8List> data, dynamic update);

  @override
  bool operator ==(dynamic other) => other != null && name == other.name;
}
