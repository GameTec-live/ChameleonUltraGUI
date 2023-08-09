import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/dfu.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'dart:math';

import 'package:nordic_dfu/nordic_dfu.dart';

Future<Uint8List> fetchFirmware(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);

  final releases = json.decode((await http.get(Uri.parse(
          "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
      .body
      .toString());

  for (var file in releases[0]["assets"]) {
    if (file["name"] ==
        "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app.zip") {
      content = await http.readBytes(Uri.parse(file["browser_download_url"]));
      break;
    }
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

Future<void> flashFile(
    ChameleonCom? connection,
    MyAppState appState,
    Uint8List applicationDat,
    Uint8List applicationBin,
    void Function(int progress) callback,
    {bool enterDFU = true,
    List<int> firmwareZip = const []}) async {
  if (applicationDat.isEmpty || applicationBin.isEmpty) {
    throw ("Empty firmware file");
  }

  // Flashing Easteregg
  var rng = Random();
  var randomNumber = rng.nextInt(100) + 1;
  appState.easteregg = false;
  if (randomNumber == 1) {
    appState.easteregg = true;
  }

  bool isBLE = appState.connector.portName.contains(":");

  if (enterDFU) {
    await connection!.enterDFUMode();
    await appState.connector.preformDisconnect();
  }

  List chameleons = [];

  while (chameleons.isEmpty) {
    await asyncSleep(250);
    chameleons = await appState.connector.availableChameleons(true);
  }

  if (chameleons.length > 1) {
    throw ("More than one Chameleon in DFU. Please connect only one at a time");
  }

  if (!isBLE) {
    await appState.connector.connectSpecific(chameleons[0]['port']);
    var dfu = ChameleonDFU(port: appState.connector);
    await appState.connector.finishRead();
    await appState.connector.open();
    await dfu.setPRN();
    await dfu.getMTU();
    await dfu.flashFirmware(0x01, applicationDat, callback);
    await dfu.flashFirmware(0x02, applicationBin, callback);
    appState.log.i("Firmware flashed!");
    appState.connector.preformDisconnect();
    appState.changesMade();
  } else {
    final tempFile = await createTempFile();
    await tempFile.writeAsBytes(Uint8List.fromList(firmwareZip));
    print(chameleons[0]['port']);
    print(tempFile.path);
    await NordicDfu().startDfu(
      chameleons[0]['port'],
      tempFile.path,
      onProgressChanged: (
        deviceAddress,
        percent,
        speed,
        avgSpeed,
        currentPart,
        partsTotal,
      ) {
        appState.log.e('deviceAddress: $deviceAddress, percent: $percent');
      },
      onError: (address, error, errorType, message) {
        print(address);
        print(error);
        print(message);
      },
      onDeviceConnected: (address) {
        print(address);
      },
      onDeviceConnecting: (address) {
        print(address);
      },
    );
  }
}
