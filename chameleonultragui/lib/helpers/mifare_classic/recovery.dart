import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

enum ChameleonKeyCheckmark { none, found, checking }

class MifareClassicRecovery {
  late ChameleonGUIState appState;
  String error;
  bool allKeysExists;
  List<Dictionary> dictionaries;
  Dictionary? selectedDictionary;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;
  List<Uint8List> cardData;
  double dumpProgress;
  double? hardnestedProgress;
  void Function() update;

  MifareClassicRecovery(
      {required this.appState,
      required this.update,
      this.error = '',
      this.allKeysExists = false,
      this.dictionaries = const [],
      this.dumpProgress = 0,
      this.selectedDictionary,
      List<ChameleonKeyCheckmark>? checkMarks,
      List<Uint8List>? validKeys,
      List<Uint8List>? cardData})
      : checkMarks =
            checkMarks ?? List.generate(80, (_) => ChameleonKeyCheckmark.none),
        validKeys = validKeys ?? List.generate(80, (_) => Uint8List(0)),
        cardData = cardData ?? List.generate(256, (_) => Uint8List(0));

  Future<void> recheckKey(Uint8List key, int startingSector) async {
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    var mifare = await appState.communicator!.detectMf1Support();
    var mf1Type = MifareClassicType.none;

    if (mifare) {
      mf1Type = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
      return;
    }

    for (var sector = startingSector;
        sector < mfClassicGetSectorCount(mf1Type);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (checkMarks[sector + (keyType * 40)] == ChameleonKeyCheckmark.none) {
          appState.log!.d(
              "Checking found key ${bytesToHex(key)} on sector $sector, key type $keyType");
          checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.checking;
          update();

          if (await appState.communicator!.mf1Auth(
              mfClassicGetSectorTrailerBlockBySector(sector),
              0x60 + keyType,
              key)) {
            // Found valid key
            validKeys[sector + (keyType * 40)] = key;
            checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.found;
          } else {
            checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.none;
          }

          update();
        }
      }
    }
  }

  Future<void> checkKeys({bool skipDefaultDictionary = false}) async {
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    var mifare = await appState.communicator!.detectMf1Support();
    var mf1Type = MifareClassicType.none;

    if (mifare) {
      mf1Type = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
      return;
    }

    validKeys = List.generate(80, (_) => Uint8List(0));
    if (mifare) {
      for (var sector = 0;
          sector < mfClassicGetSectorCount(mf1Type);
          sector++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          if (checkMarks[sector + (keyType * 40)] ==
              ChameleonKeyCheckmark.none) {
            // We are missing key, check from dictionary
            checkMarks[sector + (keyType * 40)] =
                ChameleonKeyCheckmark.checking;
            update();

            for (var key in [
              ...selectedDictionary!.keys,
              if (!skipDefaultDictionary)
                ...gMifareClassicKeys
                    .where((key) => !selectedDictionary!.keys.contains(key))
            ]) {
              appState.log!.d(
                  "Checking ${bytesToHex(key)} on sector $sector, key type $keyType");
              if (await appState.communicator!.mf1Auth(
                  mfClassicGetSectorTrailerBlockBySector(sector),
                  0x60 + keyType,
                  key)) {
                // Found valid key
                validKeys[sector + (keyType * 40)] = key;
                checkMarks[sector + (keyType * 40)] =
                    ChameleonKeyCheckmark.found;
                update();

                await recheckKey(key, sector);
                break;
              }
            }

            if (checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.checking) {
              checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.none;
              update();
            }
          }
        }
      }

      // Key check part competed, checking found keys
      allKeysExists = true;
      for (var sector = 0;
          sector < mfClassicGetSectorCount(mf1Type);
          sector++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          if (checkMarks[sector + (keyType * 40)] !=
              ChameleonKeyCheckmark.found) {
            allKeysExists = false;
          }
        }
      }
    }
  }

  Future<void> recoverKeys() async {
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    var mifare = await appState.communicator!.detectMf1Support();
    var mf1Type = MifareClassicType.none;
    error = "";

    if (mifare) {
      mf1Type = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
      return;
    }

    if (mifare) {
      // Key check part competed, checking found keys
      bool hasKey = false;
      for (var sector = 0;
          sector < mfClassicGetSectorCount(mf1Type) && !hasKey;
          sector++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          if (checkMarks[sector + (keyType * 40)] ==
              ChameleonKeyCheckmark.found) {
            hasKey = true;
            break;
          }
        }
      }

      if (!hasKey) {
        if (await appState.communicator!.checkMf1Darkside() ==
            DarksideResult.vulnerable) {
          // recover with darkside
          var data =
              await appState.communicator!.getMf1Darkside(0x03, 0x61, true, 15);
          var darkside = DarksideDart(uid: data.uid, items: []);
          checkMarks[40] = ChameleonKeyCheckmark.checking;
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
              appState.log!.d("Darkside: Found keys: $keys. Checking them...");
              for (var key in keys) {
                var keyBytes = u64ToBytes(key);
                if ((await appState.communicator!
                    .mf1Auth(0x03, 0x61, keyBytes.sublist(2, 8)))) {
                  appState.log!.i(
                      "Darkside: Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                  validKeys[40] = keyBytes.sublist(2, 8);
                  checkMarks[40] = ChameleonKeyCheckmark.found;
                  found = true;
                  await recheckKey(keyBytes, 0);
                  break;
                }
              }
            } else {
              appState.log!.d("Can't find keys, retrying...");
              data = await appState.communicator!
                  .getMf1Darkside(0x03, 0x61, false, 15);
            }
          }
        } else {
          error = "no_keys_darkside";

          return;
        }
      }

      update();

      var prng = await appState.communicator!.getMf1NTLevel();
      var validKey = Uint8List(0);
      var validKeyBlock = 0;
      var validKeyType = 0;

      if (prng != NTLevel.staticEncrypted) {
        // Check for static encrypted nonce one, just to make sure (old firmware)
        Uint8List data = await appState.communicator!.send14ARaw(
            Uint8List.fromList([0x64, 0x00]),
            autoSelect: true,
            checkResponseCrc: false);
        if (data.length == 4) {
          prng = NTLevel.hard;
        }
      } else {
        prng = NTLevel.hard;
      }

      for (var sector = 0;
          sector < mfClassicGetSectorCount(mf1Type);
          sector++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          if (checkMarks[sector + (keyType * 40)] ==
              ChameleonKeyCheckmark.found) {
            validKey = validKeys[sector + (keyType * 40)];
            validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
            validKeyType = keyType;
            break;
          }
        }
      }

      for (var sector = 0;
          sector < mfClassicGetSectorCount(mf1Type);
          sector++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          if (checkMarks[sector + (keyType * 40)] ==
              ChameleonKeyCheckmark.none) {
            checkMarks[sector + (keyType * 40)] =
                ChameleonKeyCheckmark.checking;

            update();

            var distance = await appState.communicator!
                .getMf1NTDistance(validKeyBlock, 0x60 + validKeyType, validKey);
            bool found = false;
            for (var i = 0; i < 0xFF && !found; i++) {
              List<int> keys = [];
              NestedNonces nonces;
              if (prng == NTLevel.hard) {
                hardnestedProgress = 0;
                update();
                var result = await collectHardnestedNonces(
                    validKeyBlock,
                    0x60 + validKeyType,
                    validKey,
                    mfClassicGetSectorTrailerBlockBySector(sector),
                    0x60 + keyType);

                if (result is String) {
                  checkMarks[sector + (keyType * 40)] =
                      ChameleonKeyCheckmark.none;
                  error = result;
                  return;
                } else {
                  nonces = result as NestedNonces;
                }
              } else {
                nonces = await appState.communicator!.getMf1NestedNonces(
                    validKeyBlock,
                    0x60 + validKeyType,
                    validKey,
                    mfClassicGetSectorTrailerBlockBySector(sector),
                    0x60 + keyType,
                    level: prng);
              }

              if (prng == NTLevel.weak) {
                var nested = NestedDart(
                    uid: distance.uid,
                    distance: distance.distance,
                    nt0: nonces.nonces[0].nt,
                    nt0Enc: nonces.nonces[0].ntEnc,
                    par0: nonces.nonces[0].parity,
                    nt1: nonces.nonces[1].nt,
                    nt1Enc: nonces.nonces[1].ntEnc,
                    par1: nonces.nonces[1].parity);

                keys = await recovery.nested(nested);
              } else if (prng == NTLevel.static) {
                var nested = StaticNestedDart(
                  uid: distance.uid,
                  keyType: 0x60 + validKeyType,
                  nt0: nonces.nonces[0].nt,
                  nt0Enc: nonces.nonces[0].ntEnc,
                  nt1: nonces.nonces[1].nt,
                  nt1Enc: nonces.nonces[1].ntEnc,
                );

                keys = await recovery.staticNested(nested);
              } else if (prng == NTLevel.hard) {
                var nested =
                    HardNestedDart(nonces: nonces.getHardNested(distance.uid));
                keys = await recovery.hardNested(nested);
                hardnestedProgress = null;
              }

              if (keys.isNotEmpty) {
                appState.log!.d("Found keys: $keys. Checking them...");

                for (var key in keys) {
                  var keyBytes = u64ToBytes(key).sublist(2, 8);
                  if ((await appState.communicator!.mf1Auth(
                      mfClassicGetSectorTrailerBlockBySector(sector),
                      0x60 + keyType,
                      keyBytes))) {
                    appState.log!
                        .i("Found valid key! Key ${bytesToHex(keyBytes)}");
                    found = true;
                    validKeys[sector + (keyType * 40)] = keyBytes;
                    checkMarks[sector + (keyType * 40)] =
                        ChameleonKeyCheckmark.found;
                    await recheckKey(keyBytes, sector);

                    break;
                  }
                }
              } else {
                appState.log!.e("Can't find keys, retrying...");
              }
            }
          }
        }
      }
    }
    update();
    allKeysExists = true;
  }

  Future<void> dumpData() async {
    cardData = List.generate(256, (_) => Uint8List(0));

    var mifare = await appState.communicator!.detectMf1Support();
    var mf1Type = MifareClassicType.none;

    if (mifare) {
      mf1Type = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
      return;
    }

    bool isMifareClassicEV1 =
        await appState.communicator!.mf1Auth(0x45, 0x61, gMifareClassicKeys[3]);

    if (isMifareClassicEV1) {
      validKeys[16] = gMifareClassicKeys[4]; // MFC EV1 SIGNATURE 16 A
      validKeys[16 + 40] = gMifareClassicKeys[5]; // MFC EV1 SIGNATURE 16 B
      validKeys[17] = gMifareClassicKeys[6]; // MFC EV1 SIGNATURE 17 A
      validKeys[17 + 40] = gMifareClassicKeys[3]; // MFC EV1 SIGNATURE 17 B
    }

    for (var sector = 0;
        sector < mfClassicGetSectorCount(mf1Type, isEV1: isMifareClassicEV1);
        sector++) {
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          appState.log!
              .d("Dumping sector $sector, block $block with key $keyType");

          if (validKeys[sector + (keyType * 40)].isEmpty) {
            appState.log!.w("Skipping missing key");
            cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
                Uint8List(16);
            continue;
          }

          var blockData = await appState.communicator!.mf1ReadBlock(
              block + mfClassicGetFirstBlockCountBySector(sector),
              0x60 + keyType,
              validKeys[sector + (keyType * 40)]);

          if (blockData.isEmpty) {
            if (keyType == 1) {
              blockData = Uint8List(16);
            } else {
              continue;
            }
          }

          if (mfClassicGetSectorTrailerBlockBySector(sector) ==
              block + mfClassicGetFirstBlockCountBySector(sector)) {
            // set keys in sector trailer
            if (validKeys[sector].isNotEmpty) {
              blockData.setRange(0, 6, validKeys[sector]);
            }

            if (validKeys[sector + 40].isNotEmpty) {
              blockData.setRange(10, 16, validKeys[sector + 40]);
            }
          }

          cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
              blockData;

          dumpProgress = (block + mfClassicGetFirstBlockCountBySector(sector)) /
              (mfClassicGetBlockCount(mf1Type));

          update();

          break;
        }
      }
    }
  }

  Future<dynamic> collectHardnestedNonces(int block, int keyType,
      Uint8List knownKey, int targetBlock, int targetKeyType) async {
    NestedNonces nonces = NestedNonces(nonces: []);
    while (true) {
      var collectedNonces = await appState.communicator!.getMf1NestedNonces(
          block, keyType, knownKey, targetBlock, targetKeyType,
          level: NTLevel.hard);
      nonces.nonces.addAll(collectedNonces.nonces);
      List info = nonces.getNoncesInfo();
      appState.log!.d(
          "Collected ${nonces.nonces.length} nonces, sum ${info[0]}, num ${info[1]}");

      if (nonces.nonces.isEmpty) {
        return "old_firmware";
      }

      if (info[1] == 1) {
        return "static_encrypted_nonce";
      }

      hardnestedProgress = info[1] / 256;
      update();
      if (info[1] == 256) {
        if ([
          0,
          32,
          56,
          64,
          80,
          96,
          104,
          112,
          120,
          128,
          136,
          144,
          152,
          160,
          176,
          192,
          200,
          224,
          256
        ].contains(info[0])) {
          break;
        }

        appState.log!.e("Got wrong sum, trying to collect nonces again...");
        nonces.nonces = [];
      }
    }

    return nonces;
  }
}
