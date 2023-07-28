import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SlotManagerPage extends StatefulWidget {
  const SlotManagerPage({super.key});

  @override
  SlotManagerPageState createState() => SlotManagerPageState();
}

class SlotManagerPageState extends State<SlotManagerPage> {
  var slotdata = List.filled(
    8,
    {
      'Name': 'Unused',
      'Type': 'Unused',
      'ID': 'Unused',
      'Last-updated': '00:00:00',
    },
  );

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
            Expanded(
              child: GridView(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16.0,
                  mainAxisSpacing: 16.0,
                ),
                scrollDirection: Axis.vertical,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 1);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc),
                              SizedBox(width: 5),
                              Text("Slot 1")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[0]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[0]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[0]['ID'] ?? "Unknown")
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
                                Text(slotdata[0]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 2);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc,
                                color: Colors.amber,
                              ),
                              SizedBox(width: 5),
                              Text("Slot 2")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[1]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[1]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[1]['ID'] ?? "Unknown")
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
                                Text(slotdata[1]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 3);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc,
                                color: Colors.blue,
                              ),
                              SizedBox(width: 5),
                              Text("Slot 3")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[2]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[2]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[2]['ID'] ?? "Unknown")
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
                                Text(slotdata[2]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 4);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc,
                                color: Colors.green,
                              ),
                              SizedBox(width: 5),
                              Text("Slot 4")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[3]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[3]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[3]['ID'] ?? "Unknown")
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
                                Text(slotdata[3]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 5);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc,
                                color: Colors.deepPurple,
                              ),
                              SizedBox(width: 5),
                              Text("Slot 5")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[4]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[4]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[4]['ID'] ?? "Unknown")
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
                                Text(slotdata[4]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 6);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc,
                                color: Colors.deepOrange,
                              ),
                              SizedBox(width: 5),
                              Text("Slot 6")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[5]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[5]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[5]['ID'] ?? "Unknown")
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
                                Text(slotdata[5]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 7);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc,
                                color: Colors.pink,
                              ),
                              SizedBox(width: 5),
                              Text("Slot 7")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[6]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[6]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[6]['ID'] ?? "Unknown")
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
                                Text(slotdata[6]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardSelectDialog(context, 8);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
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
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.nfc,
                                color: Colors.teal,
                              ),
                              SizedBox(width: 5),
                              Text("Slot 8")
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.credit_card),
                              const SizedBox(width: 5),
                              Text(slotdata[7]['Name'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.wifi),
                              const SizedBox(width: 5),
                              Text(slotdata[7]['Type'] ?? "Unknown")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 5),
                              Text(slotdata[7]['ID'] ?? "Unknown")
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
                                Text(slotdata[7]['Last-updated'] ?? "00:00:00"),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
      delegate: CardSearchDelegate(tags, gridPosition),
    );
  }
}

class CardSearchDelegate extends SearchDelegate<String> {
  final List<ChameleonTagSave> cards;
  final int gridPosition;

  CardSearchDelegate(this.cards, this.gridPosition);

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
              await connection.enableSlot(gridPosition, true);
              await connection.activateSlot(gridPosition);
              await connection.setDefaultDataToSlot(gridPosition, card.tag);
              for (var blockOffset = 0;
                  blockOffset < card.data.length;
                  blockOffset++) {
                await connection.setMf1BlockData(
                    blockOffset ~/ 16, card.data[blockOffset]);
              }
              var cardData = ChameleonCard(
                  uid: hexToBytes(card.uid.replaceAll(" ", "")),
                  atqa: card.atqa,
                  sak: card.sak);
              await connection.setMf1AntiCollision(cardData);
              await connection.saveSlotData();
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
