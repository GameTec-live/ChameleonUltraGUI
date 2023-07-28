import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
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

enum ChameleonKeyCheckmark { none, found, checking }

enum ChameleonMifareClassicState {
  none,
  recovery,
  recoveryOngoing,
  dump,
  dumpOngoing,
  save
}

class ChameleonReadTagStatus {
  String uid;
  String sak;
  String atqa;
  String ats;
  String tech;
  String dumpName;
  bool allKeysExists;
  MifareClassicType type;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;
  List<Uint8List> cardData;
  double dumpProgress;
  List<ChameleonDictionary> dictionaries;
  ChameleonDictionary? selectedDictionary;
  ChameleonMifareClassicState state;

  ChameleonReadTagStatus(
      {this.uid = '',
      this.sak = '',
      this.atqa = '',
      this.ats = '',
      this.tech = '',
      this.dumpName = '',
      this.allKeysExists = false,
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

  Future<void> readCardDetails(ChameleonCom connection) async {
    status.validKeys = List.generate(80, (_) => Uint8List(0));
    status.checkMarks = List.generate(80, (_) => ChameleonKeyCheckmark.none);

    try {
      if (!await connection.isReaderDeviceMode()) {
        await connection.setReaderDeviceMode(true);
      }

      var card = await connection.scan14443aTag();
      var mifare = await connection.detectMf1Support();
      var mf1Type = MifareClassicType.none;
      if (mifare) {
        mf1Type = mfClassicGetType(card.atqa, card.sak);
      }
      setState(() {
        status.uid = bytesToHexSpace(card.uid);
        status.sak = card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();
        status.atqa = bytesToHexSpace(card.atqa);
        status.ats = "Unavailable";
        status.tech =
            mifare ? "Mifare Classic ${mfClassicGetName(mf1Type)}" : "Other";
        status.checkMarks =
            List.generate(80, (_) => ChameleonKeyCheckmark.none);
        status.type = mf1Type;
        status.state = (mf1Type != MifareClassicType.none)
            ? ChameleonMifareClassicState.recovery
            : ChameleonMifareClassicState.none;
        status.allKeysExists = false;
      });
    } on Exception catch (_) {
      // TODO: catch error
    }
  }

  Future<void> recoverKeys(ChameleonCom connection, MyAppState appState) async {
    setState(() {
      status.state = ChameleonMifareClassicState.recoveryOngoing;
    });
    try {
      if (!await connection.isReaderDeviceMode()) {
        await connection.setReaderDeviceMode(true);
      }

      var card = await connection.scan14443aTag();
      var mifare = await connection.detectMf1Support();
      var mf1Type = MifareClassicType.none;
      if (mifare) {
        mf1Type = mfClassicGetType(card.atqa, card.sak);
      } else {
        appState.log.e("Not mifare tag!");
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
                await asyncSleep(1); // Let GUI update
                if (await connection.mf1Auth(
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
        bool hasKey = false;
        bool hasAllKeys = true;
        for (var sector = 0;
            sector < mfClassicGetSectorCount(status.type);
            sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (status.checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.found) {
              hasKey = true;
            }
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
        }

        if (!hasKey) {
          if (await connection.checkMf1Darkside() ==
              ChameleonDarksideResult.vurnerable) {
            // recover with darkside
            var data = await connection.getMf1Darkside(0x03, 0x61, true, 15);
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
                appState.log.d("Darkside: Found keys: $keys. Checking them...");
                for (var key in keys) {
                  var keyBytes = u64ToBytes(key);
                  await asyncSleep(1); // Let GUI update
                  if ((await connection.mf1Auth(
                          0x03, 0x61, keyBytes.sublist(2, 8))) ==
                      true) {
                    appState.log.i(
                        "Darkside: Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                    status.validKeys[40] = keyBytes.sublist(2, 8);
                    status.checkMarks[40] = ChameleonKeyCheckmark.found;
                    found = true;
                    break;
                  }
                }
              } else {
                appState.log.d("Can't find keys, retrying...");
                data = await connection.getMf1Darkside(0x03, 0x61, false, 15);
              }
            }
          } else {
            appState.log.e("No keys and not vurnerable to darkside");
            return;
          }
        }

        setState(() {
          status.checkMarks = status.checkMarks;
        });

        var prng = await connection.getMf1NTLevel();
        if (prng == ChameleonNTLevel.hard || prng == ChameleonNTLevel.unknown) {
          // No hardnested implementation yet
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
              var distance = await connection.getMf1NTDistance(
                  validKeyBlock, 0x60 + validKeyType, validKey);
              bool found = false;
              for (var i = 0; i < 0xFF && !found; i++) {
                var nonces = await connection.getMf1NestedNonces(
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
                  appState.log.d("Found keys: $keys. Checking them...");
                  for (var key in keys) {
                    var keyBytes = u64ToBytes(key);
                    await asyncSleep(1); // Let GUI update
                    if ((await connection.mf1Auth(
                            mfClassicGetSectorTrailerBlockBySector(sector),
                            0x60 + keyType,
                            keyBytes.sublist(2, 8))) ==
                        true) {
                      appState.log.i(
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
                  appState.log.e("Can't find keys, retrying...");
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
    } on Exception catch (_) {
      // TODO: catch error
    }
  }

  Future<void> dumpData(ChameleonCom connection) async {
    setState(() {
      status.state = ChameleonMifareClassicState.dumpOngoing;
    });

    status.cardData = List.generate(256, (_) => Uint8List(0));
    for (var sector = 0;
        sector < mfClassicGetSectorCount(status.type);
        sector++) {
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          var blockData = await connection.mf1ReadBlock(
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
            blockData.setRange(0, 6, status.validKeys[sector]);
            blockData.setRange(10, 16, status.validKeys[sector + 40]);
          }
          status.cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
              blockData;

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
  }

  Future<void> saveCard(
      ChameleonCom connection, MyAppState appState, bool bin) async {
    var card = await connection.scan14443aTag();

    List<int> cardDump = [];
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

    if (bin) {
      try {
        await FileSaver.instance.saveAs(
            name: bytesToHex(card.uid),
            bytes: Uint8List.fromList(cardDump),
            ext: 'bin',
            mimeType: MimeType.other);
      } on UnimplementedError catch (_) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Please select an output file:',
          fileName: '${bytesToHex(card.uid)}.bin',
        );

        if (outputFile != null) {
          var file = File(outputFile);
          await file.writeAsBytes(Uint8List.fromList(cardDump));
        }
      }
    } else {
      var tags = appState.sharedPreferencesProvider.getChameleonTags();
      tags.add(ChameleonTagSave(
          id: const Uuid().v4(),
          uid: status.uid,
          sak: hexToBytes(status.sak)[0],
          atqa: hexToBytes(status.atqa.replaceAll(" ", "")),
          name: status.dumpName,
          tag: mfClassicGetChameleonTagType(status.type),
          data: status.cardData));
      appState.sharedPreferencesProvider.setChameleonTags(tags);
    }
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
    final isSmallScreen = screenSize.width < 800;

    double fieldFontSize = isSmallScreen ? 16 : 20;
    double checkmarkSize = isSmallScreen ? 16 : 20;

    var appState = context.watch<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    status.dictionaries =
        appState.sharedPreferencesProvider.getChameleonDictionaries();
    status.dictionaries
        .insert(0, ChameleonDictionary(id: "", name: "Empty", keys: []));
    status.selectedDictionary ??= status.dictionaries[0];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Read Card'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tag Info',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  buildFieldRow('UID', status.uid, fieldFontSize),
                  buildFieldRow('SAK', status.sak, fieldFontSize),
                  buildFieldRow('ATQA', status.atqa, fieldFontSize),
                  buildFieldRow('ATS', status.ats, fieldFontSize),
                  const SizedBox(height: 16),
                  Text(
                    'Tech: ${status.tech}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fieldFontSize),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      if (appState.connector.device == ChameleonDevice.ultra) {
                        await readCardDetails(connection);
                      } else {
                        showDialog<String>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: const Text('Unsupported Action'),
                            content: const Text(
                                'Chameleon Lite does not support reading cards',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context, 'OK'),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                    child: const Text('Read'),
                  ),
                  ...(status.type != MifareClassicType.none)
                      ? [
                          const SizedBox(height: 16),
                          const Text(
                            'Keys',
                            textAlign: TextAlign.center,
                            style: TextStyle(
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
                                      const Text("A "),
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
                                      const Text("B "),
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
                                  ...(status.type == MifareClassicType.m2k ||
                                          status.type == MifareClassicType.m4k)
                                      ? [
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Text("     "),
                                              ...List.generate(
                                                16,
                                                (index) => Padding(
                                                  padding:
                                                      const EdgeInsets.all(2),
                                                  child: SizedBox(
                                                    width: checkmarkSize,
                                                    height: checkmarkSize,
                                                    child:
                                                        Text("${index + 16}"),
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Text("A "),
                                              ...List.generate(
                                                16,
                                                (index) => Padding(
                                                  padding:
                                                      const EdgeInsets.all(2),
                                                  child: SizedBox(
                                                    width: checkmarkSize,
                                                    height: checkmarkSize,
                                                    child: buildCheckmark(
                                                        status.checkMarks[
                                                            index + 16]),
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Text("B "),
                                              ...List.generate(
                                                16,
                                                (index) => Padding(
                                                  padding:
                                                      const EdgeInsets.all(2),
                                                  child: SizedBox(
                                                    width: checkmarkSize,
                                                    height: checkmarkSize,
                                                    child: buildCheckmark(
                                                        status.checkMarks[
                                                            40 + index + 16]),
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                        ]
                                      : [],
                                  ...(status.type == MifareClassicType.m4k)
                                      ? [
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
                                                            const EdgeInsets
                                                                .all(2),
                                                        child: SizedBox(
                                                          width: checkmarkSize,
                                                          height: checkmarkSize,
                                                          child: Text(
                                                              "${index + 32}"),
                                                        ),
                                                      ),
                                                    )
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    const Text("A "),
                                                    ...List.generate(
                                                      8,
                                                      (index) => Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(2),
                                                        child: SizedBox(
                                                          width: checkmarkSize,
                                                          height: checkmarkSize,
                                                          child: buildCheckmark(
                                                              status.checkMarks[
                                                                  index + 32]),
                                                        ),
                                                      ),
                                                    )
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    const Text("B "),
                                                    ...List.generate(
                                                      8,
                                                      (index) => Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(2),
                                                        child: SizedBox(
                                                          width: checkmarkSize,
                                                          height: checkmarkSize,
                                                          child: buildCheckmark(
                                                              status.checkMarks[
                                                                  40 +
                                                                      index +
                                                                      32]),
                                                        ),
                                                      ),
                                                    )
                                                  ],
                                                ),
                                              ]))
                                        ]
                                      : []
                                ],
                              ),
                              const Spacer(),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...(status.dumpProgress != 0)
                              ? [
                                  LinearProgressIndicator(
                                      value: status.dumpProgress),
                                  const SizedBox(height: 8)
                                ]
                              : [],
                          (status.state ==
                                      ChameleonMifareClassicState.recovery ||
                                  status.state ==
                                      ChameleonMifareClassicState
                                          .recoveryOngoing)
                              ? Column(children: [
                                  const Text("Key dictionary"),
                                  const SizedBox(height: 4),
                                  DropdownButton<String>(
                                    value: status.selectedDictionary!.id,
                                    items: status.dictionaries
                                        .map<DropdownMenuItem<String>>(
                                            (ChameleonDictionary dictionary) {
                                      return DropdownMenuItem<String>(
                                        value: dictionary.id,
                                        child: Text(
                                            "${dictionary.name} (${dictionary.keys.length} keys)"),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      for (var dictionary
                                          in status.dictionaries) {
                                        if (dictionary.id == newValue) {
                                          setState(() {
                                            status.selectedDictionary =
                                                dictionary;
                                          });
                                          break;
                                        }
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: (status.state ==
                                            ChameleonMifareClassicState
                                                .recovery)
                                        ? () async {
                                            await recoverKeys(
                                                connection, appState);
                                          }
                                        : null,
                                    child: const Text('Recover keys'),
                                  )
                                ])
                              : (const Column(children: [])),
                          (status.state == ChameleonMifareClassicState.dump ||
                                  status.state ==
                                      ChameleonMifareClassicState.dumpOngoing)
                              ? (Column(children: [
                                  ElevatedButton(
                                    onPressed: (status.state ==
                                            ChameleonMifareClassicState.dump)
                                        ? () async {
                                            await dumpData(connection);
                                          }
                                        : null,
                                    child: const Text('Dump card'),
                                  ),
                                ]))
                              : (const Column(children: [])),
                          (status.state == ChameleonMifareClassicState.save)
                              ? (Center(
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          await showDialog(
                                            context: context,
                                            builder: (BuildContext context) {
                                              return AlertDialog(
                                                title: const Text(
                                                    'Enter card name'),
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
                                                      await saveCard(connection,
                                                          appState, false);
                                                      Navigator.pop(
                                                          context); // Close the modal after saving
                                                    },
                                                    child: const Text('OK'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () {
                                                      Navigator.pop(
                                                          context); // Close the modal without saving
                                                    },
                                                    child: const Text('Cancel'),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                        child: const Text('Save'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await saveCard(
                                              connection, appState, true);
                                        },
                                        child: const Text('Save as .bin'),
                                      ),
                                    ])))
                              : (const Column(children: []))
                        ]
                      : []
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
