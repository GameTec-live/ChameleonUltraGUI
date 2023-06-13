import 'dart:typed_data';

import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

enum ChameleonKeyCheckmark { none, found, checking }

class ReadCardPage extends StatefulWidget {
  const ReadCardPage({super.key});

  @override
  _ReadCardPageState createState() => _ReadCardPageState();
}

class _ReadCardPageState extends State<ReadCardPage> {
  String uid = '';
  String sak = '';
  String atqa = '';
  String ats = '';
  String tech = '';
  bool allKeysExists = false;
  MifareClassicType type = MifareClassicType.none;

  List<ChameleonKeyCheckmark> checkMarks =
      List.generate(80, (_) => ChameleonKeyCheckmark.none);

  List<Uint8List> validKeys = List.generate(80, (_) => Uint8List(0));

  Future<void> readCardDetails(ChameleonCom connection) async {
    validKeys = List.generate(80, (_) => Uint8List(0));

    try {
      if (!await connection.isReaderDeviceMode()) {
        await connection.setReaderDeviceMode(true);
      }

      var card = await connection.scan14443aTag();
      var mifare = await connection.detectMf1Support();
      var mf1Type = MifareClassicType.none;
      if (mifare) {
        mf1Type = mfClassicGetType(card.ATQA, card.SAK);
      }
      setState(() {
        uid = bytesToHexSpace(card.UID);
        sak = card.SAK.toRadixString(16).padLeft(2, '0').toUpperCase();
        atqa = bytesToHexSpace(card.ATQA);
        ats = "Unavailable";
        tech = mifare ? "Mifare Classic ${mfClassicGetName(mf1Type)}" : "Other";
        checkMarks = List.generate(80, (_) => ChameleonKeyCheckmark.none);
        type = mf1Type;
      });
    } on Exception catch (_) {
      // TODO: catch error
    }
  }

  Future<void> recoverKeys(ChameleonCom connection) async {
    try {
      if (!await connection.isReaderDeviceMode()) {
        await connection.setReaderDeviceMode(true);
      }

      var card = await connection.scan14443aTag();
      var mifare = await connection.detectMf1Support();
      var mf1Type = MifareClassicType.none;
      if (mifare) {
        mf1Type = mfClassicGetType(card.ATQA, card.SAK);
      } else {
        print("Not mifare tag!");
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
              setState(() {
                checkMarks = checkMarks;
              });
              for (var key in gMifareClassicKeys) {
                await asyncSleep(1); // Let GUI update
                if (await connection.mf1Auth(
                    mfClassicGetSectorTrailerBlockBySector(sector),
                    0x60 + keyType,
                    key)) {
                  // Found valid key
                  validKeys[sector + (keyType * 40)] = key;
                  checkMarks[sector + (keyType * 40)] =
                      ChameleonKeyCheckmark.found;
                  setState(() {
                    checkMarks = checkMarks;
                  });
                  break;
                }
              }
              if (checkMarks[sector + (keyType * 40)] ==
                  ChameleonKeyCheckmark.checking) {
                checkMarks[sector + (keyType * 40)] =
                    ChameleonKeyCheckmark.none;
                setState(() {
                  checkMarks = checkMarks;
                });
              }
            }
          }
        }
        // Key check part competed, checking found keys
        bool hasKey = false;
        bool hasAllKeys = true;
        for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            print(checkMarks[sector + (keyType * 40)]);
            print(hasKey);
            if (checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.found) {
              hasKey = true;
            }
            if (checkMarks[sector + (keyType * 40)] !=
                ChameleonKeyCheckmark.found) {
              hasAllKeys = false;
            }
          }
        }

        if (hasAllKeys) {
          // all keys exists
          setState(() {
            allKeysExists = true;
          });
          return;
        }

        if (!hasKey) {
          if (await connection.checkMf1Darkside() ==
              ChameleonDarksideResult.vurnerable) {
            // recover with darkside
            var data = await connection.getMf1Darkside(0x03, 0x61, true, 15);
            var darkside = DarksideDart(uid: data.UID, items: []);
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
                print("Darkside: Found keys: $keys. Checking them...");
                for (var key in keys) {
                  var keyBytes = u64ToBytes(key);
                  if ((await connection.mf1Auth(
                          0x03, 0x61, keyBytes.sublist(2, 8))) ==
                      true) {
                    print(
                        "Darkside: Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                    validKeys[40] = keyBytes.sublist(2, 8);
                    checkMarks[40] = ChameleonKeyCheckmark.found;
                    found = true;
                    break;
                  }
                }
              } else {
                print("Can't find keys, retrying...");
                data = await connection.getMf1Darkside(0x03, 0x61, false, 15);
              }
            }
          } else {
            print("No keys and not vurnerable to darkside");
            return;
          }
        }

        setState(() {
          checkMarks = checkMarks;
        });

        var prng = await connection.getMf1NTLevel();
        if (prng == ChameleonNTLevel.hard || prng == ChameleonNTLevel.unknown) {
          // No hardnested implementation yet
          return;
        }

        var validKey = Uint8List(0);
        var validKeyBlock = 0;
        var validKeyType = 0;

        for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
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

        for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
          for (var keyType = 0; keyType < 2; keyType++) {
            if (checkMarks[sector + (keyType * 40)] ==
                ChameleonKeyCheckmark.none) {
              checkMarks[sector + (keyType * 40)] =
                  ChameleonKeyCheckmark.checking;
              await asyncSleep(1); // Let GUI update
              setState(() {
                checkMarks = checkMarks;
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
                    uid: distance.UID,
                    distance: distance.distance,
                    nt0: nonces.nonces[0].nt,
                    nt0Enc: nonces.nonces[0].ntEnc,
                    par0: nonces.nonces[0].parity,
                    nt1: nonces.nonces[1].nt,
                    nt1Enc: nonces.nonces[1].ntEnc,
                    par1: nonces.nonces[1].parity);

                var keys = await recovery.nested(nested);
                if (keys.isNotEmpty) {
                  print("Found keys: $keys. Checking them...");
                  for (var key in keys) {
                    var keyBytes = u64ToBytes(key);
                    if ((await connection.mf1Auth(
                            mfClassicGetSectorTrailerBlockBySector(sector),
                            0x60 + keyType,
                            keyBytes.sublist(2, 8))) ==
                        true) {
                      print(
                          "Found valid key! Key ${bytesToHex(keyBytes.sublist(2, 8))}");
                      found = true;
                      validKeys[sector + (keyType * 40)] =
                          keyBytes.sublist(2, 8);
                      checkMarks[sector + (keyType * 40)] =
                          ChameleonKeyCheckmark.found;
                      await asyncSleep(1); // Let GUI update
                      break;
                    }
                  }
                } else {
                  print("Can't find keys, retrying...");
                }
              }
            }
          }
        }
        setState(() {
          checkMarks = checkMarks;
        });
      }
    } on Exception catch (_) {
      // TODO: catch error
    }
  }

  Future<void> dumpData(ChameleonCom connection) async {}

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

    double tagInfoFontSize = isSmallScreen ? 24 : 32;
    double fieldFontSize = isSmallScreen ? 16 : 20;
    double checkmarkSize = isSmallScreen ? 16 : 20;

    var appState = context.watch<MyAppState>();
    var connection = ChameleonCom(port: appState.chameleon);

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
                  Text(
                    'Tag Info',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: tagInfoFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  buildFieldRow('UID', uid, fieldFontSize),
                  buildFieldRow('SAK', sak, fieldFontSize),
                  buildFieldRow('ATQA', atqa, fieldFontSize),
                  buildFieldRow('ATS', ats, fieldFontSize),
                  const SizedBox(height: 16),
                  Text(
                    'Tech: $tech',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fieldFontSize),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      await readCardDetails(connection);
                    },
                    child: const Text('Read'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Found keys',
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
                                (type == MifareClassicType.mini) ? 5 : 16,
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
                                (type == MifareClassicType.mini) ? 5 : 16,
                                (index) => Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: SizedBox(
                                    width: checkmarkSize,
                                    height: checkmarkSize,
                                    child: buildCheckmark(checkMarks[index]),
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
                                (type == MifareClassicType.mini) ? 5 : 16,
                                (index) => Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: SizedBox(
                                    width: checkmarkSize,
                                    height: checkmarkSize,
                                    child:
                                        buildCheckmark(checkMarks[40 + index]),
                                  ),
                                ),
                              )
                            ],
                          ),
                          ...(type == MifareClassicType.m2k ||
                                  type == MifareClassicType.m4k)
                              ? [
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
                                      const Text("A "),
                                      ...List.generate(
                                        16,
                                        (index) => Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: SizedBox(
                                            width: checkmarkSize,
                                            height: checkmarkSize,
                                            child: buildCheckmark(
                                                checkMarks[index + 16]),
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
                                          padding: const EdgeInsets.all(2),
                                          child: SizedBox(
                                            width: checkmarkSize,
                                            height: checkmarkSize,
                                            child: buildCheckmark(
                                                checkMarks[40 + index + 16]),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ]
                              : [],
                          ...(type == MifareClassicType.m4k)
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
                                            const Text("A "),
                                            ...List.generate(
                                              8,
                                              (index) => Padding(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                child: SizedBox(
                                                  width: checkmarkSize,
                                                  height: checkmarkSize,
                                                  child: buildCheckmark(
                                                      checkMarks[index + 32]),
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
                                                    const EdgeInsets.all(2),
                                                child: SizedBox(
                                                  width: checkmarkSize,
                                                  height: checkmarkSize,
                                                  child: buildCheckmark(
                                                      checkMarks[
                                                          40 + index + 32]),
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
                  (!allKeysExists)
                      ? ElevatedButton(
                          onPressed: () async {
                            await recoverKeys(connection);
                          },
                          child: const Text('Recover keys'),
                        )
                      : ElevatedButton(
                          onPressed: () async {
                            await dumpData(connection);
                          },
                          child: const Text('Dump card'),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
