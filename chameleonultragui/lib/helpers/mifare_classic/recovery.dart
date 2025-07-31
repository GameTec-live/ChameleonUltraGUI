import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

extension PartitionList<E> on List<E> {
  List<List<E>> partition(int size) {
    assert(size > 0);
    final out = <List<E>>[];
    for (var i = 0; i < length; i += size) {
      final end = i + size < length ? i + size : length;
      out.add(sublist(i, end));
    }
    return out;
  }
}

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
  double? keyCheckProgress;
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

  Future<bool> checkKeysOnSector(
      List<Uint8List> keys, int keyType, int sector) async {
    Uint8List? key;
    keyCheckProgress = null;
    int chunkSize =
        appState.connector!.connectionType == ConnectionType.ble ? 32 : 64;

    if (checkMarks[sector + (keyType * 40)] != ChameleonKeyCheckmark.found) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.checking;
      update();

      int totalChunks = keys.partition(chunkSize).length;

      for (var chunk in keys.partition(chunkSize)) {
        key = await appState.communicator!.mf1AuthMultipleKeys(
            mfClassicGetSectorTrailerBlockBySector(sector),
            0x60 + keyType,
            chunk);
        if (key != null) {
          validKeys[sector + (keyType * 40)] = key;
          checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.found;
          update();

          keyCheckProgress = null;
          await recheckKey(key, sector);
          return true;
        } else if (totalChunks > 10) {
          keyCheckProgress = (keyCheckProgress ?? 0) + 1 / totalChunks;
          update();
        }
      }

      if (key == null) {
        checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.none;
        update();
      }
    }

    if (keyType == 0 &&
        checkMarks[sector] == ChameleonKeyCheckmark.found &&
        checkMarks[sector + 40] != ChameleonKeyCheckmark.found &&
        key != null) {
      Uint8List block = await appState.communicator!.mf1ReadBlock(
          mfClassicGetSectorTrailerBlockBySector(sector), 0x60 + keyType, key);
      if (block.length == 16) {
        Uint8List bKey = block.sublist(10);
        if (bytesToHex(bKey) != bytesToHex(Uint8List(6))) {
          keyCheckProgress = null;
          await recheckKey(key, sector);
          return true;
        }
      }
    }

    if (checkMarks[sector + (keyType * 40)] == ChameleonKeyCheckmark.checking) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.none;
      update();
    }

    keyCheckProgress = null;
    return false;
  }

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
        List<Uint8List> keyList = [
          ...selectedDictionary!.keys,
          if (!skipDefaultDictionary)
            ...gMifareClassicKeys
                .where((key) => !selectedDictionary!.keys.contains(key))
        ];

        for (var keyType = 0; keyType < 2; keyType++) {
          await checkKeysOnSector(keyList, keyType, sector);
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
      bool hasBackdoor = await mfClassicHasBackdoor(appState.communicator!);
      DarksideResult darkside = DarksideResult.fixed;

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
        try {
          darkside = await appState.communicator!.checkMf1Darkside();
        } catch (_) {}

        if (darkside == DarksideResult.vulnerable) {
          // recover with darkside
          var data =
              await appState.communicator!.getMf1Darkside(0x03, 0x61, true, 15);
          var darkside = DarksideDart(uid: data.uid, items: []);
          checkMarks[40] = ChameleonKeyCheckmark.checking;
          bool found = false;
          update();

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
              if (await checkKeysOnSector(mfClassicConvertKeys(keys), 1, 0)) {
                found = true;
                break;
              }
            } else {
              appState.log!.d("Can't find keys, retrying...");
              data = await appState.communicator!
                  .getMf1Darkside(0x03, 0x61, false, 15);
            }
          }
        } else if (!hasBackdoor) {
          error = "no_keys_darkside";

          return;
        }
      }

      update();

      NTLevel prng = await appState.communicator!.getMf1NTLevel();
      Uint8List validKey = Uint8List(0);
      int validKeyBlock = 0;
      int validKeyType = 0;
      int? uid;
      NestedNonces? aNonces;
      NestedNonces? bNonces;

      bool isStaticEncrypted = false;

      for (var sector = 0;
          sector < mfClassicGetSectorCount(mf1Type);
          sector++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          if (checkMarks[sector + (keyType * 40)] ==
              ChameleonKeyCheckmark.found) {
            validKey = validKeys[sector + (keyType * 40)];
            validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
            validKeyType = keyType;
            isStaticEncrypted = await mfClassicIsStaticEncrypted(
                appState.communicator!, validKeyBlock, validKeyType, validKey);
            break;
          }
        }
      }

      if (isStaticEncrypted || (validKeyType == 0 && hasBackdoor)) {
        (int, NestedNonces, NestedNonces)? response =
            await appState.communicator!.getMf1StaticEncryptedNestedAcquire(
                sectorCount: mfClassicGetSectorCount(mf1Type));

        if (response == null) {
          error = "has_no_backdoor";

          return;
        }

        (uid, aNonces, bNonces) = response;
        prng = NTLevel.backdoor;
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

            NTDistance? distance;
            NestedNonces? nonces;

            if (prng != NTLevel.backdoor) {
              distance = await appState.communicator!.getMf1NTDistance(
                  validKeyBlock, 0x60 + validKeyType, validKey);
            }

            bool found = false;
            for (var i = 0; i < 0xFF && !found; i++) {
              List<int> keys = [];

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
              } else if (prng != NTLevel.backdoor) {
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
                    uid: distance!.uid,
                    distance: distance.distance,
                    nt0: nonces!.nonces[0].nt,
                    nt0Enc: nonces.nonces[0].ntEnc,
                    par0: nonces.nonces[0].parity,
                    nt1: nonces.nonces[1].nt,
                    nt1Enc: nonces.nonces[1].ntEnc,
                    par1: nonces.nonces[1].parity);

                keys = await recovery.nested(nested);
              } else if (prng == NTLevel.static) {
                var nested = StaticNestedDart(
                  uid: distance!.uid,
                  keyType: 0x60 + validKeyType,
                  nt0: nonces!.nonces[0].nt,
                  nt0Enc: nonces.nonces[0].ntEnc,
                  nt1: nonces.nonces[1].nt,
                  nt1Enc: nonces.nonces[1].ntEnc,
                );

                keys = await recovery.staticNested(nested);
              } else if (prng == NTLevel.hard) {
                var nested = HardNestedDart(
                    nonces: nonces!.getHardNested(distance!.uid));
                keys = await recovery.hardNested(nested);
                hardnestedProgress = null;
              } else if (prng == NTLevel.backdoor) {
                checkMarks[sector + 40] = ChameleonKeyCheckmark.checking;

                var possibleAKeys = await recovery.staticEncryptedNested(
                    StaticEncryptedNestedDart(
                        uid: uid!,
                        nt: aNonces!.nonces[sector].nt,
                        ntEnc: aNonces.nonces[sector].ntEnc,
                        ntParEnc: aNonces.nonces[sector].parity));

                var possibleBKeys = await recovery.staticEncryptedNested(
                    StaticEncryptedNestedDart(
                        uid: uid,
                        nt: bNonces!.nonces[sector].nt,
                        ntEnc: bNonces.nonces[sector].ntEnc,
                        ntParEnc: bNonces.nonces[sector].parity));

                var filtered = await StaticEncryptedKeysFilterAsync.filterKeys(
                    possibleAKeys,
                    possibleBKeys,
                    aNonces.nonces[sector].nt,
                    bNonces.nonces[sector].nt);

                if (await checkKeysOnSector(
                    mfClassicConvertKeys(filtered.$2.reversed.toList()),
                    1,
                    sector)) {
                  checkMarks[sector + 40] = ChameleonKeyCheckmark.found;
                  if (await checkKeysOnSector(
                      mfClassicConvertKeys(
                          await StaticEncryptedKeysFilterAsync.findMatchingKeys(
                              bNonces.nonces[sector].nt,
                              bytesToU64(Uint8List.fromList(
                                  [0, 0, ...validKeys[sector + 40]])),
                              aNonces.nonces[sector].nt,
                              possibleAKeys)),
                      0,
                      sector)) {
                    found = true;
                    break;
                  } else if (await checkKeysOnSector(
                      mfClassicConvertKeys(filtered.$1.reversed.toList()),
                      0,
                      sector)) {
                    found = true;
                    break;
                  }
                }

                // If we didn't found in first run, we will never find them
                found = true;
                break;
              }

              if (keys.isNotEmpty) {
                appState.log!.d("Found keys: $keys. Checking them...");
                if (await checkKeysOnSector(
                    mfClassicConvertKeys(keys), keyType, sector)) {
                  found = true;
                  break;
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
