import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

class DevPage extends StatelessWidget {
  // Home Page
  const DevPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    appState.chameleon.finishRead();
    var cml = ChameleonCom(port: appState.chameleon);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Center
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: () {
                // Disconnect
                appState.chameleon.performDisconnect();
                appState.changesMade();
              },
              icon: const Icon(Icons.close),
            ),
          ),
          const Text('Chameleon Ultra GUI'), // Display dummy / debug info
          Text('Platform: ${Platform.operatingSystem}'),
          Text('Android: ${appState.onAndroid}'),
          Text('Serial protocol : ${appState.chameleon}'),
          Text('Serial devices: ${appState.chameleon.availableDevices()}'),
          Text('Chameleon connected: ${appState.chameleon.connected}'),
          Text('Chameleon device type: ${appState.chameleon.device}'),
          ElevatedButton(
            // Connect Button
            onPressed: () {
              appState.chameleon.preformConnection();
              appState.changesMade();
            },
            child: const Text('Connect'),
          ),
          ElevatedButton(
            onPressed: () {
              // appState.chameleon.sendCommand("test");
            },
            child: const Text('Send'),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              appState.log.d(
                  "Reader mode (should be true): ${await cml.isReaderDeviceMode()}");
              var card = await cml.scan14443aTag();
              appState.log.d('Card UID: ${card!.UID}');
              appState.log.d('SAK: ${card.SAK}');
              appState.log.d('ATQA: ${card.ATQA}');
            },
            child: const Column(children: [
              Text('Read card'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              appState.log.d(await cml.detectMf1Support());
            },
            child: const Column(children: [
              Text('Is MFC?'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              appState.log.d(await cml.getMf1NTLevel());
            },
            child: const Column(children: [
              Text('Get NT level'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              appState.log.d(await cml.checkMf1Darkside());
            },
            child: const Column(children: [
              Text('Check darkside'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              var distance = await cml.getMf1NTDistance(40, 0x60,
                  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
              appState.log.d("UID: ${distance!.UID}");
              appState.log.d("Distance ${distance.distance}");
            },
            child: const Column(children: [
              Text('Get distance'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              var distance = await cml.getMf1NTDistance(0, 0x60,
                  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
              bool found = false;
              for (var i = 0; i < 0xFF && !found; i++) {
                var nonces = await cml.getMf1NestedNonces(
                    0,
                    0x60,
                    Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
                    0,
                    0x61);
                var nested = NestedDart(
                    uid: distance!.UID,
                    distance: distance.distance,
                    nt0: nonces!.nonces[0].nt,
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
                    if ((await cml.mf1Auth(
                            0x03, 0x60, keyBytes.sublist(2, 8))) ==
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
              await cml.setReaderDeviceMode(true);
              var data = await cml.getMf1Darkside(0x03, 0x61, true, 15);
              var darkside = DarksideDart(uid: data!.UID, items: []);
              bool found = false;

              for (var tries = 0; tries < 0xFF && !found; tries++) {
                darkside.items.add(DarksideItemDart(
                    nt1: data!.nt1,
                    ks1: data.ks1,
                    par: data.par,
                    nr: data.nr,
                    ar: data.ar));
                var keys = await recovery.darkside(darkside);
                if (keys.isNotEmpty) {
                  appState.log.d("Found keys: $keys. Checking them...");
                  for (var key in keys) {
                    var keyBytes = u64ToBytes(key);
                    if ((await cml.mf1Auth(
                            0x03, 0x61, keyBytes.sublist(2, 8))) ==
                        true) {
                      appState.log.i(
                          "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                      found = true;
                      break;
                    }
                  }
                } else {
                  appState.log.d("Can't find keys, retrying...");
                  data = await cml.getMf1Darkside(0x03, 0x61, false, 15);
                }
              }
            },
            child: const Column(children: [
              Text('Run darkside attack on card'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              var data = await cml.mf1Auth(0x03, 0x60,
                  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
              appState.log.d(data);
              var block = await cml.mf1ReadBlock(0x02, 0x60,
                  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
              appState.log.d(block);
              block![0] = 0xFF;
              await cml.mf1WriteBlock(
                  0x02,
                  0x60,
                  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
                  block);
              block = await cml.mf1ReadBlock(0x02, 0x60,
                  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
              appState.log.d(block);
            },
            child: const Column(children: [
              Text('Auth/read/write'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              appState.log.d(
                  "Reader mode (should be true): ${await cml.isReaderDeviceMode()}");
              var card = await cml.scan14443aTag();
              appState.log.d('Card UID: ${card!.UID}');
              appState.log.d('SAK: ${card.SAK}');
              appState.log.d('ATQA: ${card.ATQA}');
              await cml.setReaderDeviceMode(false);
              await cml.setMf1AntiCollision(card);
            },
            child: const Column(children: [
              Text('Copy card UID to emulator'),
            ]),
          ),
          ElevatedButton(
            onPressed: () async {
              var name = await cml.getSlotTagName(1, ChameleonTagFrequiency.hf);
              appState.log.d(name);
              await cml.setSlotTagName(
                  1, "Hello 变色龙!", ChameleonTagFrequiency.hf);
              name = await cml.getSlotTagName(1, ChameleonTagFrequiency.hf);
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
                  ks1: 216745674933338888,
                  par: 0,
                  nr: 0,
                  ar: 0));
              darkside.items.add(DarksideItemDart(
                  nt1: 913032415,
                  ks1: 1010230244403446283,
                  par: 0,
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
        ],
      ),
    );
  }
}
