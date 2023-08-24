import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/features/flash_firmware_latest.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/recovery/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

class DebugPage extends StatelessWidget {
  // Home Page
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Center
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: () {
                // Disconnect
                appState.connector.performDisconnect();
                appState.changesMade();
              },
              icon: const Icon(Icons.close),
            ),
          ),
          const Text(
            '🐞 Chameleon Ultra GUI DEBUG MENU 🐞',
            textScaleFactor: 2,
          ),
          const Text(
            'Using this menu may brick your Chameleon PERMANENTLY',
            textScaleFactor: 2,
          ),
          const Text('⚠️ YOU HAVE BEEN WARNED ⚠️', textScaleFactor: 3),
          Text('Platform: ${appState.onWeb ? 'Web' : Platform.operatingSystem}'),
          Text('Android: ${appState.onAndroid}'),
          Text('Serial protocol : ${appState.connector}'),
          Text('Chameleon connected: ${appState.connector.connected}'),
          Text('Chameleon device type: ${appState.connector.device}'),
          ElevatedButton(
            onPressed: () async {
              await appState.communicator!.setReaderDeviceMode(true);
              var distance = await appState.communicator!.getMf1NTDistance(
                  50,
                  0x60,
                  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
              bool found = false;
              for (var i = 0; i < 0xFF && !found; i++) {
                var nonces = await appState.communicator!.getMf1NestedNonces(
                    50,
                    0x60,
                    Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
                    0,
                    0x61);
                var nested = NestedDart(
                    uid: distance.uid,
                    distance: distance.distance,
                    nt0: nonces.nonces[0].nt,
                    nt0Enc: nonces.nonces[0].ntEnc,
                    par0: nonces.nonces[0].parity,
                    nt1: nonces.nonces[1].nt,
                    nt1Enc: nonces.nonces[1].ntEnc,
                    par1: nonces.nonces[1].parity);

                var keys = await recovery.nested(nested);
                if (keys.isNotEmpty) {
                  appState.log.d("Found keys: $keys. Checking them...");
                  for (var key in keys) {
                    var keyBytes = u64ToBytes(key);
                    if ((await appState.communicator!
                            .mf1Auth(0x03, 0x61, keyBytes.sublist(2, 8))) ==
                        true) {
                      appState.log.i(
                          "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                      found = true;
                      break;
                    }
                  }
                } else {
                  appState.log.d("Can't find keys, retrying...");
                }
              }
            },
            child: const Column(children: [
              Text('Run nested attack on card'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await appState.communicator!.setReaderDeviceMode(true);
              var data = await appState.communicator!
                  .getMf1Darkside(0x03, 0x61, true, 15);
              var darkside = DarksideDart(uid: data.uid, items: []);
              bool found = false;

              for (var tries = 0; tries < 0xFF && !found; tries++) {
                darkside.items.add(DarksideItemDart(
                    nt1: data.nt1,
                    ks1: BigInt.from(data.ks1),
                    par: BigInt.from(data.par),
                    nr: data.nr,
                    ar: data.ar));
                var keys = await recovery.darkside(darkside);
                if (keys.isNotEmpty) {
                  appState.log.d("Found keys: $keys. Checking them...");
                  for (var key in keys) {
                    var keyBytes = u64ToBytes(key);
                    if ((await appState.communicator!
                            .mf1Auth(0x03, 0x61, keyBytes.sublist(2, 8))) ==
                        true) {
                      appState.log.i(
                          "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                      found = true;
                      break;
                    }
                  }
                } else {
                  appState.log.d("Can't find keys, retrying...");
                  data = await appState.communicator!
                      .getMf1Darkside(0x03, 0x61, false, 15);
                }
              }
            },
            child: const Column(children: [
              Text('Run darkside attack on card'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await appState.communicator!.setReaderDeviceMode(true);
              appState.log.d(
                  "Reader mode (should be true): ${await appState.communicator!.isReaderDeviceMode()}");
              var card = await appState.communicator!.scan14443aTag();
              appState.log.d('Card UID: ${card.uid}');
              appState.log.d('SAK: ${card.sak}');
              appState.log.d('ATQA: ${card.atqa}');
              await appState.communicator!.setReaderDeviceMode(false);
              await appState.communicator!.setMf1AntiCollision(card);
            },
            child: const Column(children: [
              Text('Copy card UID to emulator'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await appState.communicator!
                  .setSlotTagName(1, "test", TagFrequency.hf);
              var name = await appState.communicator!
                  .getSlotTagName(1, TagFrequency.hf);
              appState.log.d(name);
              await appState.communicator!
                  .setSlotTagName(1, "Hello 变色龙!", TagFrequency.hf);
              name = await appState.communicator!
                  .getSlotTagName(1, TagFrequency.hf);
              appState.log.d(name);
            },
            child: const Column(children: [
              Text('Test naming'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              var darkside = DarksideDart(uid: 2374329723, items: []);
              darkside.items.add(DarksideItemDart(
                  nt1: 913032415,
                  ks1: BigInt.parse('216745674933338888'), // Use string as this num is bigger then max int value in js
                  par: BigInt.from(0),
                  nr: 0,
                  ar: 0));
              darkside.items.add(DarksideItemDart(
                  nt1: 913032415,
                  ks1: BigInt.parse('1010230244403446283'),
                  par: BigInt.from(0),
                  nr: 1,
                  ar: 0));
              var keys = await recovery.darkside(darkside);
              appState.log.d("Darkside output: $keys");
              appState.log.d(
                  "Self test: valid key exists in list ${keys.contains(0xFFFFFFFFFFFF)}");
            },
            child: const Column(children: [
              Text('Test darkside library'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              var nested = NestedDart(
                  uid: 2374329723,
                  distance: 613,
                  nt0: 1999585272,
                  nt0Enc: 3173333529,
                  par0: 3,
                  nt1: 128306861,
                  nt1Enc: 2363514210,
                  par1: 7);
              var keys = await recovery.nested(nested);
              appState.log.d("Nested output: $keys");
              appState.log.d(
                  "Self test: valid key exists in list ${keys.contains(0xFFFFFFFFFFFF)}");
            },
            child: const Column(children: [
              Text('Test nested library'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              Uint8List applicationDat, applicationBin;

              Uint8List content = await fetchFirmware(ChameleonDevice.ultra);

              (applicationDat, applicationBin) = await unpackFirmware(content);

              flashFile(
                  appState.communicator,
                  appState,
                  applicationDat,
                  applicationBin,
                  (progress) => appState.log.d("Flashing: $progress%"),
                  firmwareZip: content);
            },
            child: const Column(children: [
              Text('💀 DFU flash ultra FW 💀'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              Uint8List applicationDat, applicationBin;

              Uint8List content = await fetchFirmware(ChameleonDevice.lite);

              (applicationDat, applicationBin) = await unpackFirmware(content);

              flashFile(
                  appState.communicator,
                  appState,
                  applicationDat,
                  applicationBin,
                  (progress) => appState.log.d("Flashing: $progress%"),
                  firmwareZip: content);
            },
            child: const Column(children: [
              Text('💀 DFU flash lite FW 💀'),
            ]),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () async {
              await appState.communicator!.factoryReset();
            },
            child: const Column(children: [
              Text('✅ Safe option: restart chameleon ✅'),
            ]),
          ),
        ],
      ),
    );
  }
}
