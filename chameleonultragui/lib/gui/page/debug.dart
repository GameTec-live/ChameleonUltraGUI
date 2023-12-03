import 'dart:io';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class DebugPage extends StatelessWidget {
  // Home Page
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
        body: SingleChildScrollView(
            child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              //Align(
              //  alignment: Alignment.topRight,
              //  child: IconButton(
              //    onPressed: () {
              //      // Disconnect
              //      appState.connector!.performDisconnect();
              //      appState.changesMade();
              //    },
              //    icon: const Icon(Icons.close),
              //  ),
              //),
              const SizedBox(height: 10),
              Text(localizations.production_logging, textScaleFactor: 1.5),
              const SizedBox(height: 5),
              Text(localizations.slow_down_warning, textScaleFactor: 0.9),
              const SizedBox(height: 10),
              if (!appState.sharedPreferencesProvider.isDebugLogging())
                ElevatedButton(
                  onPressed: () async {
                    appState.sharedPreferencesProvider.setDebugLogging(true);
                    await appState.connector!.performDisconnect();
                    appState.log = null;
                    appState.connector = null;
                    appState.changesMade();
                  },
                  child: Column(children: [
                    Text(localizations.enable_production_logging),
                  ]),
                ),
              if (appState.sharedPreferencesProvider.isDebugLogging())
                ElevatedButton(
                  onPressed: () async {
                    appState.sharedPreferencesProvider.setDebugLogging(false);
                    await appState.connector!.performDisconnect();
                    appState.log = null;
                    appState.connector = null;
                    appState.changesMade();
                  },
                  child: Column(children: [
                    Text(localizations.disable_production_logging),
                  ]),
                ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  appState.sharedPreferencesProvider.clearLogLines();
                  appState.changesMade();
                },
                child: Column(children: [
                  Text(localizations.clear_logs),
                ]),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(
                      text: appState.sharedPreferencesProvider
                          .getLogLines()
                          .join("\n")));
                },
                child: Column(children: [
                  Text(localizations.copy_logs_to_clipboard),
                ]),
              ),
              const SizedBox(height: 10),
              Text(localizations.recovery_library, textScaleFactor: 1.5),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await appState.communicator!.setReaderDeviceMode(true);
                  var distance = await appState.communicator!.getMf1NTDistance(
                      50,
                      0x60,
                      Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
                  bool found = false;
                  for (var i = 0; i < 0xFF && !found; i++) {
                    var nonces = await appState.communicator!
                        .getMf1NestedNonces(
                            50,
                            0x60,
                            Uint8List.fromList(
                                [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
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
                      appState.log!.d("Found keys: $keys. Checking them...");
                      for (var key in keys) {
                        var keyBytes = u64ToBytes(key);
                        if ((await appState.communicator!
                                .mf1Auth(0x03, 0x61, keyBytes.sublist(2, 8))) ==
                            true) {
                          appState.log!.i(
                              "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                          found = true;
                          break;
                        }
                      }
                    } else {
                      appState.log!.d("Can't find keys, retrying...");
                    }
                  }
                },
                child: Column(children: [
                  Text(localizations.nested_attack),
                ]),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await appState.communicator!.setReaderDeviceMode(true);
                  var distance = await appState.communicator!.getMf1NTDistance(
                      50,
                      0x60,
                      Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
                  bool found = false;
                  for (var i = 0; i < 0xFF && !found; i++) {
                    var nonces = await appState.communicator!
                        .getMf1NestedNonces(
                            50,
                            0x60,
                            Uint8List.fromList(
                                [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
                            0,
                            0x61,
                            isStaticNested: true);
                    var nested = StaticNestedDart(
                        uid: distance.uid,
                        keyType: 0x61,
                        nt0: nonces.nonces[0].nt,
                        nt0Enc: nonces.nonces[0].ntEnc,
                        nt1: nonces.nonces[1].nt,
                        nt1Enc: nonces.nonces[1].ntEnc);

                    var keys = await recovery.staticNested(nested);
                    if (keys.isNotEmpty) {
                      appState.log!.d("Found keys: $keys. Checking them...");
                      for (var key in keys) {
                        var keyBytes = u64ToBytes(key);
                        if ((await appState.communicator!
                                .mf1Auth(0x03, 0x61, keyBytes.sublist(2, 8))) ==
                            true) {
                          appState.log!.i(
                              "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                          found = true;
                          break;
                        }
                      }
                    } else {
                      appState.log!.d("Can't find keys, retrying...");
                    }
                  }
                },
                child: Column(children: [
                  Text(localizations.static_nested_attack),
                ]),
              ),
              const SizedBox(height: 10),
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
                        ks1: data.ks1,
                        par: data.par,
                        nr: data.nr,
                        ar: data.ar));
                    var keys = await recovery.darkside(darkside);
                    if (keys.isNotEmpty) {
                      appState.log!.d("Found keys: $keys. Checking them...");
                      for (var key in keys) {
                        var keyBytes = u64ToBytes(key);
                        if ((await appState.communicator!
                                .mf1Auth(0x03, 0x61, keyBytes.sublist(2, 8))) ==
                            true) {
                          appState.log!.i(
                              "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                          found = true;
                          break;
                        }
                      }
                    } else {
                      appState.log!.d("Can't find keys, retrying...");
                      data = await appState.communicator!
                          .getMf1Darkside(0x03, 0x61, false, 15);
                    }
                  }
                },
                child: Column(children: [
                  Text(localizations.darkside_attack),
                ]),
              ),
              const SizedBox(height: 10),
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
                  appState.log!.d("Darkside output: $keys");
                  appState.log!.d(
                      "Self test: valid key exists in list ${keys.contains(0xFFFFFFFFFFFF)}");
                },
                child: Column(children: [
                  Text(localizations.test_darkside_lib),
                ]),
              ),
              const SizedBox(height: 10),
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
                  appState.log!.d("Nested output: $keys");
                  appState.log!.d(
                      "Self test: valid key exists in list ${keys.contains(0xFFFFFFFFFFFF)}");
                },
                child: Column(children: [
                  Text(localizations.test_nested_lib),
                ]),
              ),
              const SizedBox(height: 10),
              Text(localizations.force_flashing, textScaleFactor: 1.5),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await flashFirmware(appState,
                      device: ChameleonDevice.ultra,
                      enterDFU: appState.connector!.connected);
                },
                child: Column(children: [
                  Text('💀 ${localizations.dfu_flash_ultra} 💀'),
                ]),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await flashFirmware(appState,
                      device: ChameleonDevice.lite,
                      enterDFU: appState.connector!.connected);
                },
                child: Column(children: [
                  Text('💀 ${localizations.dfu_flash_lite} 💀'),
                ]),
              ),
              const SizedBox(height: 10),
              Text(localizations.other, textScaleFactor: 1.5),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await appState.communicator!.factoryReset();
                },
                child: Column(children: [
                  Text(
                      '✅ ${localizations.safe_option}: ${localizations.restart_chameleon} ✅'),
                ]),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await appState.communicator!.setReaderDeviceMode(true);
                  var card = await appState.communicator!.scan14443aTag();
                  appState.log!.d('Card UID: ${card.uid}');
                  appState.log!.d('SAK: ${card.sak}');
                  appState.log!.d('ATQA: ${card.atqa}');
                  await appState.communicator!.setReaderDeviceMode(false);
                  await appState.communicator!.setMf1AntiCollision(card);
                },
                child: Column(children: [
                  Text(localizations.copy_uid),
                ]),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  var data = await appState.communicator!.send14ARaw(
                      Uint8List.fromList([0x40]),
                      bitLen: 7,
                      appendCrc: false,
                      autoSelect: false,
                      checkResponseCrc: false,
                      keepRfField: true);

                  if (data[0] == 0x0a) {
                    data = await appState.communicator!.send14ARaw(
                        Uint8List.fromList([0x43]),
                        appendCrc: false,
                        autoSelect: false,
                        checkResponseCrc: false,
                        keepRfField: true);
                    if (data[0] == 0x0a) {
                      for (var block = 0; block < 64; block++) {
                        data = await appState.communicator!.send14ARaw(
                            Uint8List.fromList([0x30, block]),
                            autoSelect: false,
                            keepRfField: block == 63 ? false : true);
                        appState.log!.d("$block : ${bytesToHexSpace(data)}");
                      }
                    }
                  }
                },
                child: Column(children: [
                  Text(localizations.read_gen1_card_data),
                ]),
              ),
              const SizedBox(height: 10),
            ],
          ),
        )));
  }
}
