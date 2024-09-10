import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/base.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/write/base.dart';
import 'package:chameleonultragui/helpers/t55xx/write/base.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

abstract class AbstractWriteHelper {
  final ChameleonCommunicator communicator;
  AbstractWriteHelper(this.communicator);

  bool readSupported = false; // can read data without authorization
  bool writeSupported = false; // can write data without authorization

  String get name => "Abstract"; // name in dropdown
  static String get staticName => "Abstract"; // for comparing

  bool get autoDetect => false; // is autodetect supported

  Future<bool> isMagic(dynamic data); // is current card is magic card

  bool isReady(); // card ready to be written

  Future<bool> isCompatible(
      CardSave card); // is current magic card compatible with selected dump

  List<AbstractWriteHelper> getAvailableMethods(); // get available methods

  List<AbstractWriteHelper>
      getAvailableMethodsByPriority(); // get available methods for automatic check with priority

  Future<void> getCardType() async {} // get required data from card

  List<dynamic> getExtraData() {
    return [];
  } // if you want to get data from specific helpers

  Future<void> reset() async {} // delete data from helper

  static AbstractWriteHelper? getClassByCardType(
      TagType type, ChameleonGUIState appState, void Function() update) {
    if (isMifareClassic(type)) {
      return BaseMifareClassicWriteHelper(appState.communicator!,
          recovery: MifareClassicRecovery(appState: appState, update: update));
    }

    if (isMifareUltralight(type)) {
      return BaseMifareUltralightWriteHelper(appState.communicator!);
    }

    if (type == TagType.em410X) {
      return BaseT55XXCardHelper(appState.communicator!);
    }

    return null; // writing is not supported
  }

  Future<bool> writeData(CardSave card, Function(int writeProgress) update);

  Widget getWriteWidget(BuildContext context, dynamic setState);

  List<int> getFailedBlocks() {
    return [];
  }

  bool writeWidgetSupported() {
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is AbstractWriteHelper && name == other.name;
}
