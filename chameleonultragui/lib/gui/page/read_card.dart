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

enum ChameleonMifareClassicState {
  none,
  checkKeys,
  checkKeysOngoing,
  recovery,
  recoveryOngoing,
  dump,
  dumpOngoing,
  save
}

// Refactor this

class ChameleonReadTagStatus {
  String hfUid;
  String lfUid;
  String sak;
  String atqa;
  String ats;
  String hfTech;
  String lfTech;
  String dumpName;
  String recoveryError;
  bool noHfCard;
  bool noLfCard;
  bool allKeysExists;
  bool isEV1;
  MifareClassicType type;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;
  List<Uint8List> cardData;
  double dumpProgress;
  List<Dictionary> dictionaries;
  Dictionary? selectedDictionary;
  ChameleonMifareClassicState state;

  ChameleonReadTagStatus(
      {this.hfUid = '',
      this.lfUid = '',
      this.sak = '',
      this.atqa = '',
      this.ats = '',
      this.hfTech = '',
      this.lfTech = '',
      this.dumpName = '',
      this.recoveryError = '',
      this.noHfCard = false,
      this.noLfCard = false,
      this.allKeysExists = false,
      this.isEV1 = false,
      this.type = MifareClassicType.none,
      this.dictionaries = const [],
      this.selectedDictionary,
      List<ChameleonKeyCheckmark>? checkMarks,
      List<Uint8List>? validKeys,
      List<Uint8List>? cardData,
      this.dumpProgress = 0,
      this.state = ChameleonMifareClassicState.none})
      : validKeys = validKeys ?? List.generate(80, (_) => Uint8List(0)),
        checkMarks =
            checkMarks ?? List.generate(80, (_) => ChameleonKeyCheckmark.none),
        cardData = cardData ?? List.generate(0xFF, (_) => Uint8List(0));
}

class ReadCardPage extends StatefulWidget {
  const ReadCardPage({super.key});

  @override
  ReadCardPageState createState() => ReadCardPageState();
}

class ReadCardPageState extends State<ReadCardPage> {
  ChameleonReadTagStatus status = ChameleonReadTagStatus();
  Future<void> readHFInfo(ChameleonGUIState appState) async {
    status.validKeys = List.generate(80, (_) => Uint8List(0));
    status.checkMarks = List.generate(80, (_) => ChameleonKeyCheckmark.none);

    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      var card = await appState.communicator!.scan14443aTag();
      var mifare = await appState.communicator!.detectMf1Support();
      var mf1Type = MifareClassicType.none;
      bool isEV1 = false;
      if (mifare) {
        mf1Type = mfClassicGetType(card.atqa, card.sak);
        isEV1 = (await appState.communicator!
            .mf1Auth(0x45, 0x61, gMifareClassicKeys[3]));
      }
      setState(() {
        status.hfUid = bytesToHexSpace(card.uid);
        status.sak = card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();
        status.atqa = bytesToHexSpace(card.atqa);
        status.ats = "Unavailable";
        status.hfTech = mifare
            ? "Mifare Classic ${mfClassicGetName(mf1Type)}${(isEV1) ? " EV1" : ""}"
            : "Other";
        status.isEV1 = isEV1;
        status.recoveryError = "";
        status.checkMarks =
            List.generate(80, (_) => ChameleonKeyCheckmark.none);
        status.type = mf1Type;
        status.state = (mf1Type != MifareClassicType.none)
            ? ChameleonMifareClassicState.checkKeys
            : ChameleonMifareClassicState.none;
        status.allKeysExists = false;
        status.noHfCard = false;
        status.dumpProgress = 0;
      });
    } catch (_) {
      setState(() {
        status.hfUid = "";
        status.sak = "";
        status.atqa = "";
        status.ats = "";
        status.hfTech = "";
        status.recoveryError = "";
        status.type = MifareClassicType.none;
        status.state = ChameleonMifareClassicState.none;
        status.allKeysExists = false;
        status.noHfCard = true;
        status.isEV1 = false;
      });
    }
  }

  Future<void> readLFInfo(ChameleonGUIState appState) async {
    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      var card = await appState.communicator!.readEM410X();
      if (card == "00 00 00 00 00") {
        setState(() {
          status.lfUid = "";
          status.lfTech = "";
          status.noLfCard = true;
        });
      } else {
        setState(() {
          status.lfUid = card;
          status.lfTech = "EM-Marin EM4100/EM4102";
          status.noLfCard = false;
        });
      }
    } catch (_) {
      setState(() {
        status.lfUid = "";
        status.lfTech = "";
        status.noLfCard = true;
      });
    }
  }

  Future<void> recoverKeys(ChameleonGUIState appState) async {
    setState(() {
      status.state = ChameleonMifareClassicState.recoveryOngoing;
    });
    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      var mifare = await appState.communicator!.detectMf1Support();
      var localizations = AppLocalizations.of(context)!;
      if (mifare) {
        // Key check part competed, checking found keys
        bool hasKey = false;
        for (var sector = 0;
            sector < mfClassicGetSectorCount(status.type) && !hasKey;
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (status.checkMarks[sector + (keyType * 40)] ==
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
            status.checkMarks[40] = ChameleonKeyCheckmark.checking;
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
                    status.validKeys[40] = keyBytes.sublist(2, 8);
                    status.checkMarks[40] = ChameleonKeyCheckmark.found;
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
              status.recoveryError =
                  localizations.recovery_error_no_keys_darkside;
              status.state = ChameleonMifareClassicState.recovery;
            });
            return;
          }
        }

        setState(() {
          status.checkMarks = status.checkMarks;
        });

        var prng = await appState.communicator!.getMf1NTLevel();
        if (prng != NTLevel.weak) {
          // No hardnested/staticnested implementation yet
          setState(() {
            status.recoveryError = localizations.recovery_error_no_supported;
            status.state = ChameleonMifareClassicState.recovery;
          });
          return;
        }

        var validKey = Uint8List(0);
        var validKeyBlock = 0;
        var validKeyType = 0;

        for (var sector = 0;
            sector < mfClassicGetSectorCount(status.type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (status.checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.found) {
              validKey = status.validKeys[sector + (keyType * 40)];
              validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
              validKeyType = keyType;
              break;
            }
          }
        }

        for (var sector = 0;
            sector < mfClassicGetSectorCount(status.type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (status.checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.none) {
              status.checkMarks[sector + (keyType * 40)] =
                  ChameleonKeyCheckmark.checking;
              await asyncSleep(1); // Let GUI update
              setState(() {
                status.checkMarks = status.checkMarks;
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
                      status.validKeys[sector + (keyType * 40)] =
                          keyBytes.sublist(2, 8);
                      status.checkMarks[sector + (keyType * 40)] =
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
          status.checkMarks = status.checkMarks;
          status.allKeysExists = true;
          status.state = ChameleonMifareClassicState.dump;
        });
      }
    } catch (_) {}
  }

  Future<void> checkKeys(ChameleonGUIState appState) async {
    setState(() {
      status.state = ChameleonMifareClassicState.checkKeysOngoing;
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

      status.validKeys = List.generate(80, (_) => Uint8List(0));
      if (mifare) {
        for (var sector = 0;
            sector < mfClassicGetSectorCount(mf1Type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (status.checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.none) {
              // We are missing key, check from dictionary
              status.checkMarks[sector + (keyType * 40)] =
                  ChameleonKeyCheckmark.checking;
              setState(() {
                status.checkMarks = status.checkMarks;
              });
              for (var key in [
                ...status.selectedDictionary!.keys,
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
                  status.validKeys[sector + (keyType * 40)] = key;
                  status.checkMarks[sector + (keyType * 40)] =
                      ChameleonKeyCheckmark.found;
                  setState(() {
                    status.checkMarks = status.checkMarks;
                  });
                  break;
                }
              }
              if (status.checkMarks[sector + (keyType * 40)] ==
                  ChameleonKeyCheckmark.checking) {
                status.checkMarks[sector + (keyType * 40)] =
                    ChameleonKeyCheckmark.none;
                setState(() {
                  status.checkMarks = status.checkMarks;
                });
              }
            }
          }
        }

        // Key check part competed, checking found keys
        bool hasAllKeys = true;
        for (var sector = 0;
            sector < mfClassicGetSectorCount(status.type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (status.checkMarks[sector + (keyType * 40)] !=
                ChameleonKeyCheckmark.found) {
              hasAllKeys = false;
            }
          }
        }

        if (hasAllKeys) {
          // all keys exists
          setState(() {
            status.allKeysExists = true;
            status.state = ChameleonMifareClassicState.dump;
          });
          return;
        } else {
          setState(() {
            status.allKeysExists = false;
            status.state = ChameleonMifareClassicState.recovery;
          });
        }
      }
    } catch (_) {
      setState(() {
        status.recoveryError = localizations.recovery_error_dict;
        status.state = ChameleonMifareClassicState.checkKeys;
      });
    }
  }

  Future<void> dumpData(ChameleonGUIState appState) async {
    setState(() {
      status.state = ChameleonMifareClassicState.dumpOngoing;
    });
    var localizations = AppLocalizations.of(context)!;
    status.cardData = List.generate(256, (_) => Uint8List(0));
    try {
      if (status.isEV1) {
        status.validKeys[16] = gMifareClassicKeys[4]; // MFC EV1 SIGNATURE 16 A
        status.validKeys[16 + 40] =
            gMifareClassicKeys[5]; // MFC EV1 SIGNATURE 16 B
        status.validKeys[17] = gMifareClassicKeys[6]; // MFC EV1 SIGNATURE 17 A
        status.validKeys[17 + 40] =
            gMifareClassicKeys[3]; // MFC EV1 SIGNATURE 17 B
      }

      for (var sector = 0;
          sector < mfClassicGetSectorCount(status.type, isEV1: status.isEV1);
          sector++) {
        for (var block = 0;
            block < mfClassicGetBlockCountBySector(sector);
            block++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            appState.log!
                .d("Dumping sector $sector, block $block with key $keyType");

            if (status.validKeys[sector + (keyType * 40)].isEmpty) {
              appState.log!.w("Skipping missing key");
              status.cardData[block +
                  mfClassicGetFirstBlockCountBySector(sector)] = Uint8List(16);
              continue;
            }

            var blockData = await appState.communicator!.mf1ReadBlock(
                block + mfClassicGetFirstBlockCountBySector(sector),
                0x60 + keyType,
                status.validKeys[sector + (keyType * 40)]);

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
              if (status.validKeys[sector].isNotEmpty) {
                blockData.setRange(0, 6, status.validKeys[sector]);
              }

              if (status.validKeys[sector + 40].isNotEmpty) {
                blockData.setRange(10, 16, status.validKeys[sector + 40]);
              }
            }

            status.cardData[block +
                mfClassicGetFirstBlockCountBySector(sector)] = blockData;

            setState(() {
              status.dumpProgress =
                  (block + mfClassicGetFirstBlockCountBySector(sector)) /
                      (mfClassicGetBlockCount(status.type));
            });

            await asyncSleep(1); // Let GUI update
            break;
          }
        }
      }

      setState(() {
        status.dumpProgress = 0;
        status.state = ChameleonMifareClassicState.save;
      });
    } catch (_) {
      setState(() {
        status.recoveryError = localizations.recovery_error_dump_data;
        status.state = ChameleonMifareClassicState.dump;
      });
    }
  }

  Future<void> saveHFCard(ChameleonGUIState appState,
      {bool bin = false, bool skipDump = false}) async {
    List<int> cardDump = [];
    var localizations = AppLocalizations.of(context)!;
    if (!skipDump) {
      for (var sector = 0;
          sector < mfClassicGetSectorCount(status.type);
          sector++) {
        for (var block = 0;
            block < mfClassicGetBlockCountBySector(sector);
            block++) {
          cardDump.addAll(status
              .cardData[block + mfClassicGetFirstBlockCountBySector(sector)]);
        }
      }
    }

    if (bin) {
      try {
        await FileSaver.instance.saveAs(
            name: status.hfUid.replaceAll(" ", ""),
            bytes: Uint8List.fromList(cardDump),
            ext: 'bin',
            mimeType: MimeType.other);
      } on UnimplementedError catch (_) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '${localizations.output_file}:',
          fileName: '${status.hfUid.replaceAll(" ", "")}.bin',
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
          uid: status.hfUid,
          sak: hexToBytes(status.sak)[0],
          atqa: hexToBytes(status.atqa.replaceAll(" ", "")),
          name: status.dumpName,
          tag: (skipDump)
              ? TagType.mifare1K
              : mfClassicGetChameleonTagType(status.type),
          data: status.cardData));
      appState.sharedPreferencesProvider.setCards(tags);
    }
  }

  Future<void> saveLFCard(ChameleonGUIState appState) async {
    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(CardSave(
        id: const Uuid().v4(),
        uid: status.lfUid,
        sak: 0,
        atqa: Uint8List(0),
        name: status.dumpName,
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

  // ignore_for_file: use_build_context_synchronously
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    var localizations = AppLocalizations.of(context)!;
    final isSmallScreen = screenSize.width < 800;

    double fieldFontSize = isSmallScreen ? 16 : 20;
    double checkmarkSize = isSmallScreen ? 16 : 20;

    var appState = context.watch<ChameleonGUIState>();
    status.dictionaries = appState.sharedPreferencesProvider.getDictionaries();
    status.dictionaries
        .insert(0, Dictionary(id: "", name: localizations.empty, keys: []));
    status.selectedDictionary ??= status.dictionaries[0];

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
                          localizations.uid, status.hfUid, fieldFontSize),
                      buildFieldRow(
                          localizations.sak, status.sak, fieldFontSize),
                      buildFieldRow(
                          localizations.atqa, status.atqa, fieldFontSize),
                      // buildFieldRow('ATS', status.ats, fieldFontSize),
                      const SizedBox(height: 16),
                      Text(
                        'Tech: ${status.hfTech}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: fieldFontSize),
                      ),
                      const SizedBox(height: 16),
                      if (status.noHfCard) ...[
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
                      if (status.hfUid != "") ...[
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
                                        status.dumpName = value;
                                      });
                                    },
                                  ),
                                  actions: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        await saveHFCard(appState,
                                            skipDump: true);
                                        Navigator.pop(
                                            context); // Close the modal after saving
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
                      if (status.type != MifareClassicType.none) ...[
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
                                      (status.type == MifareClassicType.mini)
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
                                      (status.type == MifareClassicType.mini)
                                          ? 5
                                          : 16,
                                      (index) => Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: SizedBox(
                                          width: checkmarkSize,
                                          height: checkmarkSize,
                                          child: buildCheckmark(
                                              status.checkMarks[index]),
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
                                      (status.type == MifareClassicType.mini)
                                          ? 5
                                          : 16,
                                      (index) => Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: SizedBox(
                                          width: checkmarkSize,
                                          height: checkmarkSize,
                                          child: buildCheckmark(
                                              status.checkMarks[40 + index]),
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                                if (status.type == MifareClassicType.m2k ||
                                    status.type == MifareClassicType.m4k) ...[
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
                                            child: buildCheckmark(
                                                status.checkMarks[index + 16]),
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
                                            child: buildCheckmark(status
                                                .checkMarks[40 + index + 16]),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ],
                                if (status.type == MifareClassicType.m4k)
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
                                                  child: buildCheckmark(status
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
                                                  child: buildCheckmark(
                                                      status.checkMarks[
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
                        if (status.recoveryError != "") ...[
                          const SizedBox(height: 16),
                          ErrorMessage(errorMessage: status.recoveryError),
                        ],
                        const SizedBox(height: 12),
                        if (status.dumpProgress != 0) ...[
                          LinearProgressIndicator(value: status.dumpProgress),
                          const SizedBox(height: 8)
                        ],
                        if (status.state ==
                                ChameleonMifareClassicState.recovery ||
                            status.state ==
                                ChameleonMifareClassicState.recoveryOngoing)
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: (status.state ==
                                          ChameleonMifareClassicState.recovery)
                                      ? () async {
                                          await recoverKeys(appState);
                                        }
                                      : null,
                                  child: Text(localizations.recover_keys),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: (status.state ==
                                          ChameleonMifareClassicState.recovery)
                                      ? () async {
                                          await dumpData(appState);
                                        }
                                      : null,
                                  child: Text(localizations.dump_partial_data),
                                )
                              ]),
                        if (status.state ==
                                ChameleonMifareClassicState.checkKeys ||
                            status.state ==
                                ChameleonMifareClassicState.checkKeysOngoing)
                          Column(children: [
                            Text(localizations.additional_key_dict),
                            const SizedBox(height: 4),
                            DropdownButton<String>(
                              value: status.selectedDictionary!.id,
                              items: status.dictionaries
                                  .map<DropdownMenuItem<String>>(
                                      (Dictionary dictionary) {
                                return DropdownMenuItem<String>(
                                  value: dictionary.id,
                                  child: Text(
                                      "${dictionary.name} (${dictionary.keys.length} ${localizations.keys.toLowerCase()})"),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                for (var dictionary in status.dictionaries) {
                                  if (dictionary.id == newValue) {
                                    setState(() {
                                      status.selectedDictionary = dictionary;
                                    });
                                    break;
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: (status.state ==
                                      ChameleonMifareClassicState.checkKeys)
                                  ? () async {
                                      await checkKeys(appState);
                                    }
                                  : null,
                              child: Text(localizations.check_keys_dict),
                            )
                          ]),
                        if (status.state == ChameleonMifareClassicState.dump ||
                            status.state ==
                                ChameleonMifareClassicState.dumpOngoing)
                          Column(children: [
                            ElevatedButton(
                              onPressed: (status.state ==
                                      ChameleonMifareClassicState.dump)
                                  ? () async {
                                      await dumpData(appState);
                                    }
                                  : null,
                              child: Text(localizations.dump_card),
                            ),
                          ]),
                        if (status.state == ChameleonMifareClassicState.save)
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
                                                status.dumpName = value;
                                              });
                                            },
                                          ),
                                          actions: [
                                            ElevatedButton(
                                              onPressed: () async {
                                                await saveHFCard(appState);
                                                Navigator.pop(
                                                    context); // Close the modal after saving
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
                          localizations.uid, status.lfUid, fieldFontSize),
                      const SizedBox(height: 16),
                      Text(
                        'Tech: ${status.lfTech}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: fieldFontSize),
                      ),
                      const SizedBox(height: 16),
                      if (status.noLfCard) ...[
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
                      if (status.lfUid != "") ...[
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
                                        status.dumpName = value;
                                      });
                                    },
                                  ),
                                  actions: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        await saveLFCard(appState);
                                        Navigator.pop(
                                            context); // Close the modal after saving
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
