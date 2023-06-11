import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

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
  List<bool> checkMarks = List.generate(80, (_) => false);

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
        checkMarks = List.generate(80, (_) => false);
      });
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

  Widget buildCheckmark(bool value) {
    return Icon(
      value ? Icons.check : Icons.close,
      color: value ? Colors.green : Colors.red,
    );
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
                            children: List.generate(
                              16,
                              (index) => Padding(
                                padding: const EdgeInsets.all(2),
                                child: SizedBox(
                                  width: checkmarkSize,
                                  height: checkmarkSize,
                                  child: buildCheckmark(checkMarks[index]),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: List.generate(
                              16,
                              (index) => Padding(
                                padding: const EdgeInsets.all(2),
                                child: SizedBox(
                                  width: checkmarkSize,
                                  height: checkmarkSize,
                                  child: buildCheckmark(checkMarks[40 + index]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {},
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
