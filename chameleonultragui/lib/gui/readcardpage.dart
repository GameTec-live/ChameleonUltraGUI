import 'dart:math';

import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

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
  MifareClassicType type = MifareClassicType.none;

  List<ChameleonKeyCheckmark> checkMarks =
      List.generate(80, (_) => ChameleonKeyCheckmark.none);

  Future<void> readCardDetails(ChameleonCom connection) async {
    try {
      if (!await connection.isReaderDeviceMode()) {
        await connection.setReaderDeviceMode(true);
      }

      var card = await connection.scan14443aTag();
      var mifare = await connection.detectMf1Support();
      var mf1_type = MifareClassicType.none;
      if (mifare) {
        mf1_type = mfClassicGetType(card.ATQA, card.SAK);
      }
      setState(() {
        uid = bytesToHexSpace(card.UID);
        sak = card.SAK.toRadixString(16).padLeft(2, '0').toUpperCase();
        atqa = bytesToHexSpace(card.ATQA);
        ats = "Unavailable";
        tech = mifare ? "Mifare Classic ${mfClassicGetName(type)}" : "Other";
        checkMarks = List.generate(80, (_) => ChameleonKeyCheckmark.none);
        type = mf1_type;
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
      if (mifare) {
        for (var sector = 0; sector < mfClassicGetSectorCount(type); sector++) {
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
                    sector * 4 + 3, 0x60 + keyType, key)) {
                  // Found valid key
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
      }
    } on Exception catch (_) {
      // TODO: catch error
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

    double tagInfoFontSize = isSmallScreen ? 24 : 32;
    double fieldFontSize = isSmallScreen ? 16 : 20;
    double checkmarkSize = isSmallScreen ? 16 : 20;

    var appState = context.watch<MyAppState>();
    var connection = ChameleonCom(port: appState.chameleon);
    print(type);
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
                  ElevatedButton(
                    onPressed: () async {
                      await recoverKeys(connection);
                    },
                    child: const Text('Recover keys'),
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
