import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/files.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/foundation.dart';

Future<void> flashFirmwareZip(MyAppState appState, [AbstractSerial? connector]) async {
  connector ??= appState.connector;

  var connection = ChameleonCommunicator(port: connector);
  Uint8List applicationDat, applicationBin;

  FileResult? file = await pickFile(appState);
  if (file == null) {
    appState.log.d("Empty file picked");
    return;
  }

  (applicationDat, applicationBin) = await unpackFirmware(file.bytes);

  appState.log.d('Start flashing file');
  await flashFile(connection, appState, applicationDat, applicationBin,
      (progress) => appState.setProgressBar(progress / 100),
      firmwareZip: file.bytes,
      enterDFU: !kIsWeb);
  appState.log.d('Done flashing file');
}