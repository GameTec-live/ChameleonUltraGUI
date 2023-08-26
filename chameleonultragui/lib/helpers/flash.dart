import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/dfu.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/protobuf/dfu-cc.pb.dart';
import 'dart:math';

Future<Uint8List> fetchFirmwareFromReleases(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);
  String error = "";

  try {
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var file in releases[0]["assets"]) {
      if (file["name"] ==
          "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app.zip") {
        content = await http.readBytes(Uri.parse(file["browser_download_url"]));
        break;
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return content;
}

Future<Uint8List> fetchFirmwareFromActions(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);
  String error = "";

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] ==
              "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app" &&
          artifact["workflow_run"]["head_branch"] == "main") {
        content = await http.readBytes(Uri.parse(
            "https://nightly.link/RfidResearchGroup/ChameleonUltra/suites/${artifact["workflow_run"]["id"]}/artifacts/${artifact["id"]}"));
        break;
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return content;
}

Future<Uint8List> fetchFirmware(ChameleonDevice device) async {
  var content = await fetchFirmwareFromActions(device);

  if (content.isEmpty) {
    content = await fetchFirmwareFromReleases(device);
  }

  return content;
}

Future<String> latestAvailableCommit(ChameleonDevice device) async {
  String error = "";

  try {
    final artifacts = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts")))
        .body
        .toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] ==
              "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app" &&
          artifact["workflow_run"]["head_branch"] == "main") {
        return artifact["workflow_run"]["head_sha"];
      }
    }
  } catch (_) {}

  try {
    final releases = json.decode((await http.get(Uri.parse(
            "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
        .body
        .toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var release in releases) {
      if (release["author"]["login"] == "github-actions[bot]") {
        return release["target_commitish"];
      }
    }
  } catch (_) {}

  if (error.isNotEmpty) {
    throw error;
  }

  return "";
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

Future<void> flashFirmware(MyAppState appState) async {
  Uint8List applicationDat, applicationBin;

  Uint8List content = await fetchFirmware(appState.connector.device);

  (applicationDat, applicationBin) = await unpackFirmware(content);

  flashFile(appState.communicator, appState, applicationDat, applicationBin,
      (progress) => appState.setProgressBar(progress / 100),
      firmwareZip: content);
}

Future<void> flashFirmwareZip(MyAppState appState) async {
  Uint8List applicationDat, applicationBin;

  FilePickerResult? result = await FilePicker.platform.pickFiles();

  if (result != null) {
    File file = File(result.files.single.path!);

    (applicationDat, applicationBin) =
        await unpackFirmware(await file.readAsBytes());

    flashFile(appState.communicator, appState, applicationDat, applicationBin,
        (progress) => appState.setProgressBar(progress / 100),
        firmwareZip: await file.readAsBytes());
  }
}

Future<void> flashFile(
    ChameleonCommunicator? connection,
    MyAppState appState,
    Uint8List applicationDat,
    Uint8List applicationBin,
    void Function(int progress) callback,
    {bool enterDFU = true,
    List<int> firmwareZip = const []}) async {
  validateFiles(applicationDat, applicationBin);

  // Flashing easter egg
  var rng = Random();
  var randomNumber = rng.nextInt(100) + 1;
  appState.easterEgg = false;
  if (randomNumber == 1) {
    appState.easterEgg = true;
  }

  if (enterDFU) {
    await connection!.enterDFUMode();
    await appState.connector.performDisconnect();
  }

  if (appState.connector.isOpen) {
    await appState.connector.performDisconnect();
  }

  if (Platform.isAndroid) {
    // BLE appears bit earlier than USB
    await asyncSleep(1000);
  }

  List<Chameleon> chameleons = [];

  while (chameleons.isEmpty) {
    await asyncSleep(250);
    chameleons = await appState.connector.availableChameleons(true);
  }

  var toFlash = chameleons[0];
  var isBLE = toFlash.type == ConnectionType.ble;

  if (toFlash.type == ConnectionType.ble) {
    for (var chameleon in chameleons) {
      if (chameleon.type != ConnectionType.ble) {
        toFlash = chameleon;
        isBLE = false;
        break;
      }
    }
  }

  if (chameleons.length > 1 && !isBLE) {
    throw ("More than one Chameleon in DFU. Please connect only one at a time");
  }

  await appState.connector.connectSpecificDevice(chameleons[0].port);

  var dfu = DFUCommunicator(
      port: appState.connector,
      viaBLE: toFlash.type == ConnectionType.ble); // isBLE shouldn't used here
  await dfu.setPRN();
  await dfu.getMTU();
  appState.changesMade();
  await dfu.flashFirmware(0x01, applicationDat, callback);
  await dfu.flashFirmware(0x02, applicationBin, callback);
  appState.log.i("Firmware flashed!");
  appState.connector.performDisconnect();
  await asyncSleep(500); // allow exit DFU mode
  appState.changesMade();
}
