import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

class SlotManagerPage extends StatefulWidget {
  const SlotManagerPage({super.key});

  @override
  SlotManagerPageState createState() => SlotManagerPageState();
}

class SlotManagerPageState extends State<SlotManagerPage> {
  List<Map<String, String>> slotData = List.generate(
    8,
    (_) => {
      'hfName': 'Loading',
      'lfName': 'Loading',
      'Last-updated': 'Not implemented',
    },
  );

  int currentFunctionIndex = 0;

  Future<void> executeNextFunction() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    if (currentFunctionIndex < 8) {
      try {
        slotData[currentFunctionIndex]['hfName'] = await connection
            .getSlotTagName(currentFunctionIndex, ChameleonTagFrequiency.hf);
      } catch (_) {
        slotData[currentFunctionIndex]['hfName'] = "";
      }

      try {
        slotData[currentFunctionIndex]['lfName'] = await connection
            .getSlotTagName(currentFunctionIndex, ChameleonTagFrequiency.lf);
      } catch (_) {
        slotData[currentFunctionIndex]['lfName'] = "";
      }

      if (slotData[currentFunctionIndex]['hfName']!.isEmpty) {
        slotData[currentFunctionIndex]['hfName'] = "Emtpy";
      }

      if (slotData[currentFunctionIndex]['lfName']!.isEmpty) {
        slotData[currentFunctionIndex]['lfName'] = "Emtpy";
      }

      setState(() {
        currentFunctionIndex++;
      });
    }
  }

  void reloadPage() {
    setState(() {
      currentFunctionIndex = 0;
    });
    var appState = context.read<MyAppState>();
    appState.changesMade();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Slot Manager"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            FutureBuilder(
              future: executeNextFunction(),
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                return Expanded(
                  child: Card(
                    child: StaggeredGridView.countBuilder(
                      padding: const EdgeInsets.all(20),
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      itemCount: 8,
                      itemBuilder: (BuildContext context, int index) {
                        return Container(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: ElevatedButton(
                            onPressed: () {
                              cardSelectDialog(context, index);
                            },
                            style: ButtonStyle(
                              shape: MaterialStateProperty.all<
                                  RoundedRectangleBorder>(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18.0),
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.nfc),
                                      const SizedBox(width: 5),
                                      Text("Slot ${index + 1}")
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.credit_card),
                                      const SizedBox(width: 5),
                                      Text(slotData[index]['hfName'] ??
                                          "Unknown")
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.wifi),
                                      const SizedBox(width: 5),
                                      Text(slotData[index]['lfName'] ??
                                          "Unknown")
                                    ],
                                  ),
                                  Expanded(
                                      child: Align(
                                    alignment: Alignment.bottomRight,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const Icon(Icons.access_time),
                                        const SizedBox(width: 5),
                                        Text(slotData[index]['Last-updated'] ??
                                            "Not implemented"),
                                      ],
                                    ),
                                  )),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      staggeredTileBuilder: (int index) =>
                          const StaggeredTile.fit(1),
                    ),
                  ),
                );
              },
            )
          ],
        ),
      ),
    );
  }

  Future<String?> cardSelectDialog(BuildContext context, int gridPosition) {
    var appState = context.read<MyAppState>();
    var tags = appState.sharedPreferencesProvider.getChameleonTags();

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(tags, gridPosition, reloadPage),
    );
  }
}

class CardSearchDelegate extends SearchDelegate<String> {
  final List<ChameleonTagSave> cards;
  final int gridPosition;
  final dynamic refresh;

  CardSearchDelegate(this.cards, this.gridPosition, this.refresh);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = cards.where((card) =>
        card.name.toLowerCase().contains(query.toLowerCase()) ||
        chameleonTagToString(card.tag)
            .toLowerCase()
            .contains(query.toLowerCase()));

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return Column(
          children: [
            ElevatedButton(
              onPressed: () {
                // Set card here
                Navigator.pop(context);
              },
              child: ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text(card.name),
                subtitle: Text(chameleonTagToString(card.tag)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = cards.where((card) =>
        card.name.toLowerCase().contains(query.toLowerCase()) ||
        chameleonTagToString(card.tag)
            .toLowerCase()
            .contains(query.toLowerCase()));
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return ListTile(
          leading: const Icon(Icons.credit_card),
          title: Text(card.name),
          subtitle: Text(chameleonTagToString(card.tag)),
          onTap: () async {
            if ([
              ChameleonTag.mifareMini,
              ChameleonTag.mifare1K,
              ChameleonTag.mifare2K,
              ChameleonTag.mifare4K
            ].contains(card.tag)) {
              await connection.setReaderDeviceMode(false);
              await connection.enableSlot(gridPosition, true);
              await connection.activateSlot(gridPosition);
              await connection.setDefaultDataToSlot(gridPosition, card.tag);
              var cardData = ChameleonCard(
                  uid: hexToBytes(card.uid.replaceAll(" ", "")),
                  atqa: card.atqa,
                  sak: card.sak);
              await connection.setMf1AntiCollision(cardData);
              for (var blockOffset = 0;
                  blockOffset < card.data.length;
                  blockOffset++) {
                await connection.setMf1BlockData(
                    blockOffset, card.data[blockOffset]);
              }
              await connection.setSlotTagName(
                  gridPosition,
                  (card.name.isEmpty) ? "No name" : card.name,
                  ChameleonTagFrequiency.hf);
              await connection.saveSlotData();
              appState.changesMade();
              refresh();
            } else if (card.tag == ChameleonTag.em410X) {
              await connection.setReaderDeviceMode(false);
              await connection.enableSlot(gridPosition, true);
              await connection.activateSlot(gridPosition);
              await connection.setDefaultDataToSlot(gridPosition, card.tag);
              await connection.setEM410XEmulatorID(
                  hexToBytes(card.uid.replaceAll(" ", "")));
              await connection.setSlotTagName(
                  gridPosition,
                  (card.name.isEmpty) ? "No name" : card.name,
                  ChameleonTagFrequiency.lf);
              await connection.saveSlotData();
              appState.changesMade();
              refresh();
            } else {
              appState.log.e("Can't write this card type yet.");
            }
            close(context, card.name);
          },
        );
      },
    );
  }
}
