import 'dart:typed_data';

import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

Future<void> asyncSleep(int milliseconds) async {
  await Future.delayed(Duration(milliseconds: milliseconds));
}

// Mifare Classic keys from Proxmark3
final gMifareClassicKeysList = {
  0xFFFFFFFFFFFF, // DEFAULT KEY (FIRST KEY USED BY PROGRAM IF NO USER DEFINED KEY)
  0xA0A1A2A3A4A5, // NFCFORUM MAD KEY
  0xD3F7D3F7D3F7, // NDEF PUBLIC KEY
  0x4B791BEA7BCC, // MFC EV1 SIGNATURE 17 B
  0x5C8FF9990DA2, // MFC EV1 SIGNATURE 16 A
  0xD01AFEEB890A, // MFC EV1 SIGNATURE 16 B
  0x75CCB59C9BED, // MFC EV1 SIGNATURE 17 A
  0xFC00018778F7, // PUBLIC TRANSPORT
  0x6471A5EF2D1A, // SIMONSVOSS
  0x4E3552426B32, // ID06
  0xEF1232AB18A0, // SCHLAGE
  0xB7BF0C13066E, // GALLAGHER
  0x135B88A94B8B, // SAFLOK
  0x2A2C13CC242A, // DORMA KABA
  0x5A7A52D5E20D, // BOSCH
  0x314B49474956, // VIGIK1 A
  0x564C505F4D41, // VIGIK1 B
  0x021209197591, // BTCINO
  0x484558414354, // INTRATONE
  0xEC0A9B1A9E06, // VINGCARD
  0x66B31E64CA4B, // VINGCARD
  0x97F5DA640B18, // BANGKOK METRO KEY
  0xA8844B0BCA06, // METRO VALENCIA KEY
  0xE4410EF8ED2D, // ARMENIAN METRO
  0x857464D3AAD1, // HTC EINDHOVEN KEY
  0x08B386463229, // TROIKA
  0xE00000000000, // ICOPY
  0x199404281970, // NSP A
  0x199404281998, // NSP B
  0x6A1987C40A21, // SALTO
  0x7F33625BC129, // SALTO
  0x484944204953, // HID
  0x204752454154, // HID
  0x3B7E4FD575AD, // HID
  0x11496F97752A, // HID
  0x3E65E4FB65B3, // GYM
  0x000000000000, // BLANK KEY
  0xB0B1B2B3B4B5,
  0xAABBCCDDEEFF,
  0x1A2B3C4D5E6F,
  0x123456789ABC,
  0x010203040506,
  0x123456ABCDEF,
  0xABCDEF123456,
  0x4D3A99C351DD,
  0x1A982C7E459A,
  0x714C5C886E97,
  0x587EE5F9350F,
  0xA0478CC39091,
  0x533CB6C723F6,
  0x8FD0A4F256E9,
  0x0000014B5C31,
  0xB578F38A5C61,
  0x96A301BCE267,
};

final gMifareClassicKeys = gMifareClassicKeysList
    .map((key) => Uint8List.fromList([
          (key >> 40) & 0xFF,
          (key >> 32) & 0xFF,
          (key >> 24) & 0xFF,
          (key >> 16) & 0xFF,
          (key >> 8) & 0xFF,
          key & 0xFF,
        ]))
    .toList();

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
  List<ChameleonKeyCheckmark> checkMarks =
      List.generate(80, (_) => ChameleonKeyCheckmark.none);

  Future<void> readCardDetails(ChameleonCom connection) async {
    try {
      if (!await connection.isReaderDeviceMode()) {
        await connection.setReaderDeviceMode(true);
      }

      var card = await connection.scan14443aTag();
      var mifare = await connection.detectMf1Support();
      setState(() {
        uid = bytesToHexSpace(card.UID);
        sak = card.SAK.toRadixString(16).padLeft(2, '0').toUpperCase();
        atqa = bytesToHexSpace(card.ATQA);
        ats = "Unavailable";
        tech = mifare ? "Mifare Classic" : "Other";
        checkMarks = List.generate(80, (_) => ChameleonKeyCheckmark.none);
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
        for (var sector = 0; sector < 16; sector++) {
          // TODO: separate 1k from 4k
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
        textAlign: (MediaQuery.of(context).size.width < 600)
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
    final isSmallScreen = screenSize.width < 600;

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
                                16,
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
                                16,
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
                                16,
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
