import 'package:flutter/material.dart';
import 'package:chameleonultragui/main.dart';

class SlotManagerPage extends StatefulWidget {
  @override
  _SlotManagerPageState createState() => _SlotManagerPageState();
}

class _SlotManagerPageState extends State<SlotManagerPage> {
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
                      cardselectdialog(context, 1);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc),
                              SizedBox(width: 5),
                              Text("Slot 1")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardselectdialog(context, 2);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc, color: Colors.amber,),
                              SizedBox(width: 5),
                              Text("Slot 2")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardselectdialog(context, 3);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc, color: Colors.blue,),
                              SizedBox(width: 5),
                              Text("Slot 3")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardselectdialog(context, 4);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc, color: Colors.green,),
                              SizedBox(width: 5),
                              Text("Slot 4")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Last Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardselectdialog(context, 5);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc, color: Colors.deepPurple,),
                              SizedBox(width: 5),
                              Text("Slot 5")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardselectdialog(context, 6);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc, color: Colors.deepOrange,),
                              SizedBox(width: 5),
                              Text("Slot 6")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardselectdialog(context, 7);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc, color: Colors.pink,),
                              SizedBox(width: 5),
                              Text("Slot 7")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      cardselectdialog(context, 8);
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.nfc, color: Colors.teal,),
                              SizedBox(width: 5),
                              Text("Slot 8")
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.credit_card),
                              SizedBox(width: 5),
                              Text("Card Name")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.wifi),
                              SizedBox(width: 5),
                              Text("Card Type")
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.insert_drive_file),
                              SizedBox(width: 5),
                              Text("Card ID")
                            ],
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.access_time),
                                  SizedBox(width: 5),
                                  Text("Changed: 00:00:00"),
                                ],
                              ),
                            )
                          ),
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

  Future<String?> cardselectdialog(BuildContext context, int gridPosition) {
    final List<Map<String, dynamic>> cards = [
      {
        'name': 'Card Name',
        'type': 'Card Type',
        'color': Colors.amber,
      },
      {
        'name': 'Card Name 2',
        'type': 'Card Type 2',
        'color': Colors.blue,
      },
    ];

    cards.sort((a, b) => a['name'].compareTo(b['name']));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(cards),
    );
  }
}

class CardSearchDelegate extends SearchDelegate<String> {
  final List<Map<String, dynamic>> cards;

  CardSearchDelegate(this.cards);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = cards.where((card) =>
        card['name'].toLowerCase().contains(query.toLowerCase()) ||
        card['type'].toLowerCase().contains(query.toLowerCase()));
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return Column(
          children: [
            ElevatedButton(
              onPressed: () {
                // Set card here
              },
              child: ListTile(
                leading: Icon(Icons.credit_card, color: card['color']),
                title: Text(card['name']),
                subtitle: Text(card['type']),
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
        card['name'].toLowerCase().contains(query.toLowerCase()) ||
        card['type'].toLowerCase().contains(query.toLowerCase()));
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return ListTile(
          leading: Icon(Icons.credit_card, color: card['color']),
          title: Text(card['name']),
          subtitle: Text(card['type']),
          onTap: () {
            close(context, card['name']);
          },
        );
      },
    );
  }
}