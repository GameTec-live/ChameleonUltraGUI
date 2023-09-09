import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_saver/file_saver.dart';

// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:uuid/uuid.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

enum ChameleonKeyCheckmark { none, found, checking }

enum MifareClassicState {
  none,
  checkKeys,
  checkKeysOngoing,
  recovery,
  recoveryOngoing,
  dump,
  dumpOngoing,
  save
}

// cardExist true because we don't show error to user if nothing is done
class HFCardInfo {
  String uid;
  String sak;
  String atqa;
  String tech;
  bool cardExist;

  HFCardInfo(
      {this.uid = '',
      this.sak = '',
      this.atqa = '',
      this.tech = '',
      this.cardExist = true});
}

class LFCardInfo {
  String uid;
  String tech;
  bool cardExist;

  LFCardInfo({this.uid = '', this.tech = '', this.cardExist = true});
}

class MifareClassicInfo {
  bool isEV1;
  double dumpProgress;
  MifareClassicRecoveryInfo recovery;
  MifareClassicType type;
  MifareClassicState state;
  List<Uint8List> cardData;

  MifareClassicInfo(
      {this.isEV1 = false,
      this.dumpProgress = 0,
      this.type = MifareClassicType.none,
      this.state = MifareClassicState.none,
      MifareClassicRecoveryInfo? recovery,
      List<Uint8List>? cardData})
      : recovery = recovery ?? MifareClassicRecoveryInfo(),
        cardData = cardData ?? List.generate(0xFF, (_) => Uint8List(0));
}

class MifareClassicRecoveryInfo {
  String error;
  bool allKeysExists;
  List<Dictionary> dictionaries;
  Dictionary? selectedDictionary;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;

  MifareClassicRecoveryInfo(
      {this.error = '',
      this.allKeysExists = false,
      this.dictionaries = const [],
      this.selectedDictionary,
      List<ChameleonKeyCheckmark>? checkMarks,
      List<Uint8List>? validKeys})
      : checkMarks =
            checkMarks ?? List.generate(80, (_) => ChameleonKeyCheckmark.none),
        validKeys = validKeys ?? List.generate(80, (_) => Uint8List(0));
}

class ReadCardPage extends StatefulWidget {
  const ReadCardPage({super.key});

  @override
  ReadCardPageState createState() => ReadCardPageState();
}

class ReadCardPageState extends State<ReadCardPage> {
  String dumpName = "";
  HFCardInfo hfInfo = HFCardInfo();
  LFCardInfo lfInfo = LFCardInfo();
  MifareClassicInfo mfcInfo = MifareClassicInfo();

  Future<void> readHFInfo(ChameleonGUIState appState) async {
    setState(() {
      hfInfo = HFCardInfo();
      mfcInfo = MifareClassicInfo();
    });

    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      var card = await appState.communicator!.scan14443aTag();
      var mifare = await appState.communicator!.detectMf1Support();
      bool isEV1 = (await appState.communicator!
          .mf1Auth(0x45, 0x61, gMifareClassicKeys[3]));

      setState(() {
        hfInfo.uid = bytesToHexSpace(card.uid);
        hfInfo.sak = card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();
        hfInfo.atqa = bytesToHexSpace(card.atqa);
        mfcInfo.isEV1 = isEV1;
        mfcInfo.type = mfClassicGetType(card.atqa, card.sak);
        mfcInfo.state = (mfcInfo.type != MifareClassicType.none)
            ? MifareClassicState.checkKeys
            : MifareClassicState.none;
        hfInfo.tech = mifare
            ? "Mifare Classic ${mfClassicGetName(mfcInfo.type)}${isEV1 ? " EV1" : ""}"
            : "Other";
      });
    } catch (_) {
      setState(() {
        hfInfo.cardExist = false;
      });
    }
  }

  Future<void> readLFInfo(ChameleonGUIState appState) async {
    try {
      setState(() {
        lfInfo = LFCardInfo();
      });

      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      var card = await appState.communicator!.readEM410X();
      if (card != "00 00 00 00 00") {
        setState(() {
          lfInfo.uid = card;
          lfInfo.tech = "EM-Marin EM4100/EM4102";
        });
      } else {
        setState(() {
          lfInfo.cardExist = false;
        });
      }
    } catch (_) {}
  }

  Future<void> recoverKeys(ChameleonGUIState appState) async {
    setState(() {
      mfcInfo.state = MifareClassicState.recoveryOngoing;
    });

    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      var mifare = await appState.communicator!.detectMf1Support();

      if (!context.mounted) {
        return;
      }

      var localizations = AppLocalizations.of(context)!;
      if (mifare) {
        // Key check part competed, checking found keys
        bool hasKey = false;
        for (var sector = 0;
            sector < mfClassicGetSectorCount(mfcInfo.type) && !hasKey;
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (mfcInfo.recovery.checkMarks[sector + (keyType * 40)] ==
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
            var data = await appState.communicator!
                .getMf1Darkside(0x03, 0x61, true, 15);
            var darkside = DarksideDart(uid: data.uid, items: []);
            mfcInfo.recovery.checkMarks[40] = ChameleonKeyCheckmark.checking;
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
                appState.log!
                    .d("Darkside: Found keys: $keys. Checking them...");
                for (var key in keys) {
                  var keyBytes = u64ToBytes(key);
                  await asyncSleep(1); // Let GUI update
                  if ((await appState.communicator!
                      .mf1Auth(0x03, 0x61, keyBytes.sublist(2, 8)))) {
                    appState.log!.i(
                        "Darkside: Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                    mfcInfo.recovery.validKeys[40] = keyBytes.sublist(2, 8);
                    mfcInfo.recovery.checkMarks[40] =
                        ChameleonKeyCheckmark.found;
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
          } else {
            setState(() {
              mfcInfo.recovery.error =
                  localizations.recovery_error_no_keys_darkside;
              mfcInfo.state = MifareClassicState.recovery;
            });
            return;
          }
        }

        setState(() {
          mfcInfo.recovery.checkMarks = mfcInfo.recovery.checkMarks;
        });

        var prng = await appState.communicator!.getMf1NTLevel();
        if (prng != NTLevel.weak) {
          // No hardnested/staticnested implementation yet
          setState(() {
            mfcInfo.recovery.error = localizations.recovery_error_no_supported;
            mfcInfo.state = MifareClassicState.recovery;
          });
          return;
        }

        var validKey = Uint8List(0);
        var validKeyBlock = 0;
        var validKeyType = 0;

        for (var sector = 0;
            sector < mfClassicGetSectorCount(mfcInfo.type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (mfcInfo.recovery.checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.found) {
              validKey = mfcInfo.recovery.validKeys[sector + (keyType * 40)];
              validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
              validKeyType = keyType;
              break;
            }
          }
        }

        for (var sector = 0;
            sector < mfClassicGetSectorCount(mfcInfo.type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (mfcInfo.recovery.checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.none) {
              mfcInfo.recovery.checkMarks[sector + (keyType * 40)] =
                  ChameleonKeyCheckmark.checking;
              await asyncSleep(1); // Let GUI update
              setState(() {
                mfcInfo.recovery.checkMarks = mfcInfo.recovery.checkMarks;
              });
              var distance = await appState.communicator!.getMf1NTDistance(
                  validKeyBlock, 0x60 + validKeyType, validKey);
              bool found = false;
              for (var i = 0; i < 0xFF && !found; i++) {
                var nonces = await appState.communicator!.getMf1NestedNonces(
                    validKeyBlock,
                    0x60 + validKeyType,
                    validKey,
                    mfClassicGetSectorTrailerBlockBySector(sector),
                    0x60 + keyType);
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
                    await asyncSleep(1); // Let GUI update
                    if ((await appState.communicator!.mf1Auth(
                        mfClassicGetSectorTrailerBlockBySector(sector),
                        0x60 + keyType,
                        keyBytes.sublist(2, 8)))) {
                      appState.log!.i(
                          "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                      found = true;
                      mfcInfo.recovery.validKeys[sector + (keyType * 40)] =
                          keyBytes.sublist(2, 8);
                      mfcInfo.recovery.checkMarks[sector + (keyType * 40)] =
                          ChameleonKeyCheckmark.found;
                      await asyncSleep(1); // Let GUI update
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

        setState(() {
          mfcInfo.recovery.checkMarks = mfcInfo.recovery.checkMarks;
          mfcInfo.recovery.allKeysExists = true;
          mfcInfo.state = MifareClassicState.dump;
        });
      }
    } catch (_) {}
  }

  Future<void> checkKeys(ChameleonGUIState appState) async {
    setState(() {
      mfcInfo.state = MifareClassicState.checkKeysOngoing;
    });

    var localizations = AppLocalizations.of(context)!;
    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }
      var card = await appState.communicator!.scan14443aTag();
      var mifare = await appState.communicator!.detectMf1Support();
      var mf1Type = MifareClassicType.none;
      if (mifare) {
        mf1Type = mfClassicGetType(card.atqa, card.sak);
      } else {
        appState.log!.e("Not Mifare Classic tag!");
        return;
      }

      mfcInfo.recovery.validKeys = List.generate(80, (_) => Uint8List(0));
      if (mifare) {
        for (var sector = 0;
            sector < mfClassicGetSectorCount(mf1Type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (mfcInfo.recovery.checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.none) {
              // We are missing key, check from dictionary
              mfcInfo.recovery.checkMarks[sector + (keyType * 40)] =
                  ChameleonKeyCheckmark.checking;
              setState(() {
                mfcInfo.recovery.checkMarks = mfcInfo.recovery.checkMarks;
              });
              for (var key in [
                ...mfcInfo.recovery.selectedDictionary!.keys,
                ...gMifareClassicKeys
              ]) {
                appState.log!
                    .d("Checking $key on sector $sector, key type $keyType");
                await asyncSleep(1); // Let GUI update
                if (await appState.communicator!.mf1Auth(
                    mfClassicGetSectorTrailerBlockBySector(sector),
                    0x60 + keyType,
                    key)) {
                  // Found valid key
                  mfcInfo.recovery.validKeys[sector + (keyType * 40)] = key;
                  mfcInfo.recovery.checkMarks[sector + (keyType * 40)] =
                      ChameleonKeyCheckmark.found;
                  setState(() {
                    mfcInfo.recovery.checkMarks = mfcInfo.recovery.checkMarks;
                  });
                  break;
                }
              }
              if (mfcInfo.recovery.checkMarks[sector + (keyType * 40)] ==
                  ChameleonKeyCheckmark.checking) {
                mfcInfo.recovery.checkMarks[sector + (keyType * 40)] =
                    ChameleonKeyCheckmark.none;
                setState(() {
                  mfcInfo.recovery.checkMarks = mfcInfo.recovery.checkMarks;
                });
              }
            }
          }
        }

        // Key check part competed, checking found keys
        bool hasAllKeys = true;
        for (var sector = 0;
            sector < mfClassicGetSectorCount(mfcInfo.type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (mfcInfo.recovery.checkMarks[sector + (keyType * 40)] !=
                ChameleonKeyCheckmark.found) {
              hasAllKeys = false;
            }
          }
        }

        if (hasAllKeys) {
          // all keys exists
          setState(() {
            mfcInfo.recovery.allKeysExists = true;
            mfcInfo.state = MifareClassicState.dump;
          });
          return;
        } else {
          setState(() {
            mfcInfo.recovery.allKeysExists = false;
            mfcInfo.state = MifareClassicState.recovery;
          });
        }
      }
    } catch (_) {
      setState(() {
        mfcInfo.recovery.error = localizations.recovery_error_dict;
        mfcInfo.state = MifareClassicState.checkKeys;
      });
    }
  }

  Future<void> dumpData(ChameleonGUIState appState) async {
    setState(() {
      mfcInfo.state = MifareClassicState.dumpOngoing;
    });

    var localizations = AppLocalizations.of(context)!;
    mfcInfo.cardData = List.generate(256, (_) => Uint8List(0));
    try {
      if (mfcInfo.isEV1) {
        mfcInfo.recovery.validKeys[16] =
            gMifareClassicKeys[4]; // MFC EV1 SIGNATURE 16 A
        mfcInfo.recovery.validKeys[16 + 40] =
            gMifareClassicKeys[5]; // MFC EV1 SIGNATURE 16 B
        mfcInfo.recovery.validKeys[17] =
            gMifareClassicKeys[6]; // MFC EV1 SIGNATURE 17 A
        mfcInfo.recovery.validKeys[17 + 40] =
            gMifareClassicKeys[3]; // MFC EV1 SIGNATURE 17 B
      }

      for (var sector = 0;
          sector < mfClassicGetSectorCount(mfcInfo.type, isEV1: mfcInfo.isEV1);
          sector++) {
        for (var block = 0;
            block < mfClassicGetBlockCountBySector(sector);
            block++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            appState.log!
                .d("Dumping sector $sector, block $block with key $keyType");

            if (mfcInfo.recovery.validKeys[sector + (keyType * 40)].isEmpty) {
              appState.log!.w("Skipping missing key");
              mfcInfo.cardData[block +
                  mfClassicGetFirstBlockCountBySector(sector)] = Uint8List(16);
              continue;
            }

            var blockData = await appState.communicator!.mf1ReadBlock(
                block + mfClassicGetFirstBlockCountBySector(sector),
                0x60 + keyType,
                mfcInfo.recovery.validKeys[sector + (keyType * 40)]);

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
              if (mfcInfo.recovery.validKeys[sector].isNotEmpty) {
                blockData.setRange(0, 6, mfcInfo.recovery.validKeys[sector]);
              }

              if (mfcInfo.recovery.validKeys[sector + 40].isNotEmpty) {
                blockData.setRange(
                    10, 16, mfcInfo.recovery.validKeys[sector + 40]);
              }
            }

            mfcInfo.cardData[block +
                mfClassicGetFirstBlockCountBySector(sector)] = blockData;

            setState(() {
              mfcInfo.dumpProgress =
                  (block + mfClassicGetFirstBlockCountBySector(sector)) /
                      (mfClassicGetBlockCount(mfcInfo.type));
            });

            await asyncSleep(1); // Let GUI update
            break;
          }
        }
      }

      setState(() {
        mfcInfo.dumpProgress = 0;
        mfcInfo.state = MifareClassicState.save;
      });
    } catch (_) {
      setState(() {
        mfcInfo.recovery.error = localizations.recovery_error_dump_data;
        mfcInfo.state = MifareClassicState.dump;
      });
    }
  }

  Future<void> saveHFCard(ChameleonGUIState appState,
      {bool bin = false, bool skipDump = false}) async {
    List<int> cardDump = [];
    var localizations = AppLocalizations.of(context)!;
    if (!skipDump) {
      for (var sector = 0;
          sector < mfClassicGetSectorCount(mfcInfo.type);
          sector++) {
        for (var block = 0;
            block < mfClassicGetBlockCountBySector(sector);
            block++) {
          cardDump.addAll(mfcInfo
              .cardData[block + mfClassicGetFirstBlockCountBySector(sector)]);
        }
      }
    }

    if (bin) {
      try {
        await FileSaver.instance.saveAs(
            name: hfInfo.uid.replaceAll(" ", ""),
            bytes: Uint8List.fromList(cardDump),
            ext: 'bin',
            mimeType: MimeType.other);
      } on UnimplementedError catch (_) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '${localizations.output_file}:',
          fileName: '${hfInfo.uid.replaceAll(" ", "")}.bin',
        );

        if (outputFile != null) {
          var file = File(outputFile);
          await file.writeAsBytes(Uint8List.fromList(cardDump));
        }
      }
    } else {
      var tags = appState.sharedPreferencesProvider.getCards();
      tags.add(CardSave(
          id: const Uuid().v4(),
          uid: hfInfo.uid,
          sak: hexToBytes(hfInfo.sak)[0],
          atqa: hexToBytes(hfInfo.atqa.replaceAll(" ", "")),
          name: dumpName,
          tag: (skipDump)
              ? TagType.mifare1K
              : mfClassicGetChameleonTagType(mfcInfo.type),
          data: mfcInfo.cardData));
      appState.sharedPreferencesProvider.setCards(tags);
    }
  }

  Future<void> saveLFCard(ChameleonGUIState appState) async {
    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(CardSave(
        id: const Uuid().v4(),
        uid: lfInfo.uid,
        sak: 0,
        atqa: Uint8List(0),
        name: dumpName,
        tag: TagType.em410X,
        data: []));
    appState.sharedPreferencesProvider.setCards(tags);
  }

  Widget buildFieldRow(String label, String value, double fontSize) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        '$label: $value',
        textAlign: (MediaQuery.of(context).size.width < 800)
            ? TextAlign.left
            : TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }

  Widget buildCheckmark(ChameleonKeyCheckmark value) {
    if (value != ChameleonKeyCheckmark.checking) {
      return Icon(
        value == ChameleonKeyCheckmark.found ? Icons.check : Icons.close,
        color: value == ChameleonKeyCheckmark.found ? Colors.green : Colors.red,
      );
    } else {
      return const CircularProgressIndicator();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    var localizations = AppLocalizations.of(context)!;
    final isSmallScreen = screenSize.width < 800;

    double fieldFontSize = isSmallScreen ? 16 : 20;
    double checkmarkSize = isSmallScreen ? 16 : 20;

    var appState = context.watch<ChameleonGUIState>();
    mfcInfo.recovery.dictionaries =
        appState.sharedPreferencesProvider.getDictionaries();
    mfcInfo.recovery.dictionaries
        .insert(0, Dictionary(id: "", name: localizations.empty, keys: []));
    mfcInfo.recovery.selectedDictionary ??= mfcInfo.recovery.dictionaries[0];

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.read_card),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        localizations.hf_tag_info,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildFieldRow(
                          localizations.uid, hfInfo.uid, fieldFontSize),
                      buildFieldRow(
                          localizations.sak, hfInfo.sak, fieldFontSize),
                      buildFieldRow(
                          localizations.atqa, hfInfo.atqa, fieldFontSize),
                      const SizedBox(height: 16),
                      Text(
                        'Tech: ${hfInfo.tech}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: fieldFontSize),
                      ),
                      const SizedBox(height: 16),
                      if (!hfInfo.cardExist) ...[
                        ErrorMessage(errorMessage: localizations.no_card_found),
                        const SizedBox(height: 16)
                      ],
                      ElevatedButton(
                        onPressed: () async {
                          if (appState.connector!.device ==
                              ChameleonDevice.ultra) {
                            await readHFInfo(appState);
                          } else if (appState.connector!.device ==
                              ChameleonDevice.lite) {
                            showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                title: Text(localizations.no_supported),
                                content: Text(localizations.lite_no_read,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                        context, localizations.ok),
                                    child: Text(localizations.ok),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            appState.changesMade();
                          }
                        },
                        child: Text(localizations.read),
                      ),
                      if (hfInfo.uid != "") ...[
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(localizations.enter_name),
                                  content: TextField(
                                    onChanged: (value) {
                                      setState(() {
                                        dumpName = value;
                                      });
                                    },
                                  ),
                                  actions: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        await saveHFCard(appState,
                                            skipDump: true);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                      child: Text(localizations.ok),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(
                                            context); // Close the modal without saving
                                      },
                                      child: Text(localizations.cancel),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          child: Text(localizations.save_only_uid),
                        ),
                      ],
                      if (mfcInfo.type != MifareClassicType.none) ...[
                        const SizedBox(height: 16),
                        Text(
                          localizations.keys,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text("     "),
                                    ...List.generate(
                                      (mfcInfo.type == MifareClassicType.mini)
                                          ? 5
                                          : 16,
                                      (index) => Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: SizedBox(
                                          width: checkmarkSize,
                                          height: checkmarkSize,
                                          child: Text("$index"),
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(localizations.letter_space("A")),
                                    ...List.generate(
                                      (mfcInfo.type == MifareClassicType.mini)
                                          ? 5
                                          : 16,
                                      (index) => Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: SizedBox(
                                          width: checkmarkSize,
                                          height: checkmarkSize,
                                          child: buildCheckmark(mfcInfo
                                              .recovery.checkMarks[index]),
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(localizations.letter_space("B")),
                                    ...List.generate(
                                      (mfcInfo.type == MifareClassicType.mini)
                                          ? 5
                                          : 16,
                                      (index) => Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: SizedBox(
                                          width: checkmarkSize,
                                          height: checkmarkSize,
                                          child: buildCheckmark(mfcInfo
                                              .recovery.checkMarks[40 + index]),
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                                if (mfcInfo.type == MifareClassicType.m2k ||
                                    mfcInfo.type == MifareClassicType.m4k) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text("     "),
                                      ...List.generate(
                                        16,
                                        (index) => Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: SizedBox(
                                            width: checkmarkSize,
                                            height: checkmarkSize,
                                            child: Text("${index + 16}"),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(localizations.letter_space("A")),
                                      ...List.generate(
                                        16,
                                        (index) => Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: SizedBox(
                                            width: checkmarkSize,
                                            height: checkmarkSize,
                                            child: buildCheckmark(mfcInfo
                                                .recovery
                                                .checkMarks[index + 16]),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(localizations.letter_space("B")),
                                      ...List.generate(
                                        16,
                                        (index) => Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: SizedBox(
                                            width: checkmarkSize,
                                            height: checkmarkSize,
                                            child: buildCheckmark(mfcInfo
                                                .recovery
                                                .checkMarks[40 + index + 16]),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ],
                                if (mfcInfo.type == MifareClassicType.m4k)
                                  Center(
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Text("     "),
                                            ...List.generate(
                                              8,
                                              (index) => Padding(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                child: SizedBox(
                                                  width: checkmarkSize,
                                                  height: checkmarkSize,
                                                  child: Text("${index + 32}"),
                                                ),
                                              ),
                                            )
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text(localizations
                                                .letter_space("A")),
                                            ...List.generate(
                                              8,
                                              (index) => Padding(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                child: SizedBox(
                                                  width: checkmarkSize,
                                                  height: checkmarkSize,
                                                  child: buildCheckmark(mfcInfo
                                                      .recovery
                                                      .checkMarks[index + 32]),
                                                ),
                                              ),
                                            )
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text(localizations
                                                .letter_space("B")),
                                            ...List.generate(
                                              8,
                                              (index) => Padding(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                child: SizedBox(
                                                  width: checkmarkSize,
                                                  height: checkmarkSize,
                                                  child: buildCheckmark(mfcInfo
                                                          .recovery.checkMarks[
                                                      40 + index + 32]),
                                                ),
                                              ),
                                            )
                                          ],
                                        ),
                                      ]))
                              ],
                            ),
                            const Spacer(),
                          ],
                        ),
                        if (mfcInfo.recovery.error != "") ...[
                          const SizedBox(height: 16),
                          ErrorMessage(errorMessage: mfcInfo.recovery.error),
                        ],
                        const SizedBox(height: 12),
                        if (mfcInfo.dumpProgress != 0) ...[
                          LinearProgressIndicator(value: mfcInfo.dumpProgress),
                          const SizedBox(height: 8)
                        ],
                        if (mfcInfo.state == MifareClassicState.recovery ||
                            mfcInfo.state == MifareClassicState.recoveryOngoing)
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: (mfcInfo.state ==
                                          MifareClassicState.recovery)
                                      ? () async {
                                          await recoverKeys(appState);
                                        }
                                      : null,
                                  child: Text(localizations.recover_keys),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: (mfcInfo.state ==
                                          MifareClassicState.recovery)
                                      ? () async {
                                          await dumpData(appState);
                                        }
                                      : null,
                                  child: Text(localizations.dump_partial_data),
                                )
                              ]),
                        if (mfcInfo.state == MifareClassicState.checkKeys ||
                            mfcInfo.state ==
                                MifareClassicState.checkKeysOngoing)
                          Column(children: [
                            Text(localizations.additional_key_dict),
                            const SizedBox(height: 4),
                            DropdownButton<String>(
                              value: mfcInfo.recovery.selectedDictionary!.id,
                              items: mfcInfo.recovery.dictionaries
                                  .map<DropdownMenuItem<String>>(
                                      (Dictionary dictionary) {
                                return DropdownMenuItem<String>(
                                  value: dictionary.id,
                                  child: Text(
                                      "${dictionary.name} (${dictionary.keys.length} ${localizations.keys.toLowerCase()})"),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                for (var dictionary
                                    in mfcInfo.recovery.dictionaries) {
                                  if (dictionary.id == newValue) {
                                    setState(() {
                                      mfcInfo.recovery.selectedDictionary =
                                          dictionary;
                                    });
                                    break;
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: (mfcInfo.state ==
                                      MifareClassicState.checkKeys)
                                  ? () async {
                                      await checkKeys(appState);
                                    }
                                  : null,
                              child: Text(localizations.check_keys_dict),
                            )
                          ]),
                        if (mfcInfo.state == MifareClassicState.dump ||
                            mfcInfo.state == MifareClassicState.dumpOngoing)
                          Column(children: [
                            ElevatedButton(
                              onPressed:
                                  (mfcInfo.state == MifareClassicState.dump)
                                      ? () async {
                                          await dumpData(appState);
                                        }
                                      : null,
                              child: Text(localizations.dump_card),
                            ),
                          ]),
                        if (mfcInfo.state == MifareClassicState.save)
                          Center(
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                ElevatedButton(
                                  onPressed: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: Text(localizations.enter_name),
                                          content: TextField(
                                            onChanged: (value) {
                                              setState(() {
                                                dumpName = value;
                                              });
                                            },
                                          ),
                                          actions: [
                                            ElevatedButton(
                                              onPressed: () async {
                                                await saveHFCard(appState);
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                              child: Text(localizations.ok),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                Navigator.pop(
                                                    context); // Close the modal without saving
                                              },
                                              child: Text(localizations.cancel),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  child: Text(localizations.save),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    await saveHFCard(appState, bin: true);
                                  },
                                  child: Text(localizations.save_as(".bin")),
                                ),
                              ])),
                      ]
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        localizations.lf_tag_info,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildFieldRow(
                          localizations.uid, lfInfo.uid, fieldFontSize),
                      const SizedBox(height: 16),
                      Text(
                        'Tech: ${lfInfo.tech}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: fieldFontSize),
                      ),
                      const SizedBox(height: 16),
                      if (!lfInfo.cardExist) ...[
                        ErrorMessage(errorMessage: localizations.no_card_found),
                        const SizedBox(height: 16)
                      ],
                      ElevatedButton(
                        onPressed: () async {
                          if (appState.connector!.device ==
                              ChameleonDevice.ultra) {
                            await readLFInfo(appState);
                          } else if (appState.connector!.device ==
                              ChameleonDevice.lite) {
                            showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                title: Text(localizations.no_supported),
                                content: Text(localizations.lite_no_read,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                        context, localizations.ok),
                                    child: Text(localizations.ok),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            appState.changesMade();
                          }
                        },
                        child: Text(localizations.read),
                      ),
                      if (lfInfo.uid != "") ...[
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(localizations.enter_name),
                                  content: TextField(
                                    onChanged: (value) {
                                      setState(() {
                                        dumpName = value;
                                      });
                                    },
                                  ),
                                  actions: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        await saveLFCard(appState);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                      child: Text(localizations.ok),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(
                                            context); // Close the modal without saving
                                      },
                                      child: Text(localizations.cancel),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          child: Text(localizations.save),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
