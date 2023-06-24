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
                      cardselectdialog(context);
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
                      cardselectdialog(context);
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
                      cardselectdialog(context);
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
                      cardselectdialog(context);
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
                      cardselectdialog(context);
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
                      cardselectdialog(context);
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
                      cardselectdialog(context);
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
                      cardselectdialog(context);
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

  Future<String?> cardselectdialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
        AlertDialog(
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SearchBar(
                hintText: "Search for a card...",
                padding: MaterialStateProperty.all<EdgeInsets>(const EdgeInsets.symmetric(horizontal: 15)),
                leading: const Icon(Icons.search),
              ),
              const SizedBox(height: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 500,
                  width: 300,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          // Set card here
                        },
                         child: const ListTile(
                          leading: Icon(Icons.credit_card, color: Colors.amber,),
                          title: Text("Card Name"),
                          subtitle: Text("Card Type"),
                        ),
                      ),
                      const SizedBox(height: 5),
                      ElevatedButton(
                        onPressed: () {
                          // Set card here
                        },
                         child: const ListTile(
                          leading: Icon(Icons.credit_card, color: Colors.blue,),
                          title: Text("Card Name 2"),
                          subtitle: Text("Card Type 2"),
                        ),
                      ),
                    ]
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}
