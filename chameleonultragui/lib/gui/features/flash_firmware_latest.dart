import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/http.dart';
import 'package:chameleonultragui/main.dart';

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

Future<void> flashFirmwareLatest(MyAppState appState, [AbstractSerial? connector]) async {
  connector ??= appState.connector;
  var connection = ChameleonCommunicator(port: connector);
  Uint8List applicationDat, applicationBin;

  Uint8List content = await fetchFirmware(appState.connector.device);

  (applicationDat, applicationBin) = await unpackFirmware(content);

  flashFile(connection, appState, applicationDat, applicationBin,
      (progress) => appState.setProgressBar(progress / 100),
      firmwareZip: content);
}
