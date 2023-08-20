import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:chameleonultragui/helpers/http.dart';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
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
    final response = await httpGet("https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases");
    final releases = json.decode(response.body.toString());

    if (releases is! List && releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    final expectedAssetName = "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app.zip";
    for (var file in releases[0]["assets"]) {
      if (file["name"] == expectedAssetName) {
        content = await httpGetBinary(file["browser_download_url"]);
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
    final response = await httpGet("https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts");
    final artifacts = json.decode(response.body.toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    final expectedAssetName = "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app";
    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] == expectedAssetName) {
        final assetUrl = "https://nightly.link/RfidResearchGroup/ChameleonUltra/suites/${artifact["workflow_run"]["id"]}/artifacts/${artifact["id"]}";
        content = await httpGetBinary(assetUrl);
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
    final response = await httpGet("https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/actions/artifacts");
    final artifacts = json.decode(response.body.toString());

    if (artifacts.containsKey("message")) {
      error = artifacts["message"];
      throw error;
    }

    final expectedAssetName = "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app";
    for (var artifact in artifacts["artifacts"]) {
      if (artifact["name"] == expectedAssetName) {
        return artifact["workflow_run"]["head_sha"];
      }
    }
  } catch (_) {}

  try {
    final response = await httpGet("https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases");
    final releases = json.decode(response.body.toString());

    if (releases.containsKey("message")) {
      error = releases["message"];
      throw error;
    }

    for (var release in releases) {
      if (release["author"]["login"] == "github-actions[bot]") {
        return release["body"].split("Built from commit ")[1].split("\n")[0];
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

Future<void> flashFile(
    ChameleonCom? connection,
    MyAppState appState,
    Uint8List applicationDat,
    Uint8List applicationBin,
    void Function(int progress) callback,
    {bool enterDFU = true,
    List<int> firmwareZip = const []}) async {
  validateFiles(applicationDat, applicationBin);

  // Flashing Easteregg
  var rng = Random();
  var randomNumber = rng.nextInt(100) + 1;
  appState.easterEgg = false;
  if (randomNumber == 1) {
    appState.easterEgg = true;
  }

  bool isBLE = appState.connector.portName.contains(":");

  if (enterDFU) {
    await connection!.enterDFUMode();
    await appState.connector.performDisconnect();
  }

  List chameleons = [];

  while (chameleons.isEmpty) {
    await asyncSleep(250);
    chameleons = await appState.connector.availableChameleons(true);
  }

  if (chameleons.length > 1) {
    throw ("More than one Chameleon in DFU. Please connect only one at a time");
  }

  if (isBLE) {
    throw ("BLE DFU not yet supported");
  }

  await appState.connector.connectSpecific(chameleons[0]['port']);
  var dfu = ChameleonDFU(port: appState.connector);
  await appState.connector.finishRead();
  await appState.connector.open();
  await dfu.setPRN();
  await dfu.getMTU();
  await dfu.flashFirmware(0x01, applicationDat, callback);
  await dfu.flashFirmware(0x02, applicationBin, callback);
  appState.log.i("Firmware flashed!");
  appState.connector.performDisconnect();
  appState.changesMade();
}
