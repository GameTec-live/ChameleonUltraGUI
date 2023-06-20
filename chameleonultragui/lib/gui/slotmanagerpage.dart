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
                  crossAxisCount: 1,
                  crossAxisSpacing: 4.0,
                  mainAxisSpacing: 4.0,
                ),
                scrollDirection: Axis.vertical,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc),
                            Text("Slot 1")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc, color: Colors.indigo),
                            Text("Slot 2")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc, color: Colors.lime),
                            Text("Slot 3")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc, color: Colors.orange),
                            Text("Slot 4")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc, color: Colors.purple),
                            Text("Slot 5")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc, color: Colors.blue),
                            Text("Slot 6")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc, color: Colors.red),
                            Text("Slot 7")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
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
                              const Text("List of Cards Here")
                            ],
                          ),
                        ),
                      );
                    },
                    style: ButtonStyle(
                      shape: MaterialStateProperty.all<
                        RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                        ),
                     ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc, color: Colors.white),
                            Text("Slot 8")
                          ],
                        ),
                        Text("Loaded Card:"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.credit_card),
                            Text("Card Name")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi),
                            Text("Card Type")
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.insert_drive_file),
                            Text("Card ID")
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text("Last Changed: 00:00:00"),
                          )
                        ),
                      ],
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
}
