import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/dfu.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/protobuf/dfu-cc.pb.dart';
import 'dart:math';

Future<Uint8List> fetchFirmware(ChameleonDevice device) async {
  var content = await fetchFirmwareFromActions(device);

  if (content.isEmpty) {
    content = await fetchFirmwareFromReleases(device);
  }

  return content;
}

Future<(Uint8List, Uint8List)> unpackFirmware(Uint8List content) async {
  Uint8List applicationDat = Uint8List(0);
  Uint8List applicationBin = Uint8List(0);

  final archive = ZipDecoder().decodeBytes(content);

  for (var file in archive.files) {
    if (file.isFile) {
      if (file.name == "application.dat") {
        applicationDat = file.content;
      } else if (file.name == "application.bin") {
        applicationBin = file.content;
      }
    }
  }

  return (applicationDat, applicationBin);
}

Future<File> createTempFile() async {
  final tempDir = await Directory.systemTemp.createTemp('firmware');
  final tempFile = File('${tempDir.path}/flash.zip');
  return tempFile;
}

void validateFiles(Uint8List dat, Uint8List bin) {
  if (dat.isEmpty || bin.isEmpty) {
    throw ("Empty firmware file");
  }

  final metadata = Packet.fromBuffer(dat);
  if (!metadata.hasSignedCommand()) {
    throw ("Package isn't signed");
  }

  final command = metadata.signedCommand.command;
  if (!command.hasInit()) {
    throw ("Package command doesn't have init");
  }

  final hash = command.init.hash;
  final expectedHash = hash.hash.reversed;
  final actualHash = switch (hash.hashType) {
    HashType.SHA128 => sha1,
    HashType.SHA256 => sha256,
    HashType.SHA512 => sha512,
    _ => throw ("Unsupported hash type ${hash.hashType}"),
  }
      .convert(bin)
      .bytes;

  if (!const IterableEquality().equals(expectedHash, actualHash)) {
    throw ("Hashes don't match! expected: ${expectedHash.toList()}, actual: $actualHash");
  }
}

Future<void> flashFirmware(ChameleonGUIState appState,
    {ScaffoldMessengerState? scaffoldMessenger,
    ChameleonDevice? device,
    bool enterDFU = true}) async {
  Uint8List applicationDat, applicationBin;

  Uint8List content = await fetchFirmware(
      (device != null) ? device : appState.connector!.device);

  (applicationDat, applicationBin) = await unpackFirmware(content);

  flashFile(appState.communicator, appState, applicationDat, applicationBin,
      (progress) => appState.setProgressBar(progress / 100),
      firmwareZip: content,
      scaffoldMessenger: scaffoldMessenger,
      enterDFU: enterDFU);
}

Future<void> flashFirmwareZip(ChameleonGUIState appState,
    {ScaffoldMessengerState? scaffoldMessenger, bool enterDFU = true}) async {
  Uint8List applicationDat, applicationBin;

  FilePickerResult? result = await FilePicker.platform.pickFiles();

  if (result != null) {
    File file = File(result.files.single.path!);

    (applicationDat, applicationBin) =
        await unpackFirmware(await file.readAsBytes());

    flashFile(appState.communicator, appState, applicationDat, applicationBin,
        (progress) => appState.setProgressBar(progress / 100),
        firmwareZip: await file.readAsBytes(),
        scaffoldMessenger: scaffoldMessenger,
        enterDFU: enterDFU);
  }
}

Future<void> flashFile(
    ChameleonCommunicator? connection,
    ChameleonGUIState appState,
    Uint8List applicationDat,
    Uint8List applicationBin,
    void Function(int progress) callback,
    {bool enterDFU = true,
    List<int> firmwareZip = const [],
    ScaffoldMessengerState? scaffoldMessenger}) async {
  validateFiles(applicationDat, applicationBin);

  // Flashing easter egg
  var rng = Random();
  var randomNumber = rng.nextInt(100) + 1;
  appState.easterEgg = false;
  if (randomNumber == 1) {
    appState.easterEgg = true;
  }

  if (enterDFU) {
    await connection?.enterDFUMode();
    await appState.connector?.performDisconnect();
  }

  if (appState.connector!.isOpen) {
    await appState.connector!.performDisconnect();
  }

  if (Platform.isAndroid) {
    // BLE appears bit earlier than USB
    await asyncSleep(1000);
  }

  List<Chameleon> chameleons = [];

  while (chameleons.isEmpty) {
    await asyncSleep(250);
    chameleons = await appState.connector!.availableChameleons(true);
  }

  var toFlash = chameleons[0];
  Map<ConnectionType, bool> connections = {
    ConnectionType.ble: false,
    ConnectionType.usb: false
  };

  for (var chameleon in chameleons) {
    if (connections[chameleon.type]!) {
      throw ("More than one Chameleon in DFU. Please connect only one at a time");
    }

    connections[chameleon.type] = true;
  }

  if (toFlash.type == ConnectionType.ble) {
    for (var chameleon in chameleons) {
      if (chameleon.type != ConnectionType.ble) {
        toFlash = chameleon;
        break;
      }
    }
  }

  await appState.connector!.connectSpecificDevice(chameleons[0].port);

  if (scaffoldMessenger != null) {
    scaffoldMessenger.removeCurrentSnackBar();
  }

  var dfu = DFUCommunicator(appState.log!,
      port: appState.connector, viaBLE: toFlash.type == ConnectionType.ble);
  appState.changesMade();
  await dfu.setPRN();
  await dfu.getMTU();
  await dfu.flashFirmware(0x01, applicationDat, callback);
  await dfu.flashFirmware(0x02, applicationBin, callback);
  appState.log!.i("Firmware flashed!");
  appState.connector!.performDisconnect();
  await asyncSleep(500); // allow exit DFU mode
  appState.changesMade();
}
