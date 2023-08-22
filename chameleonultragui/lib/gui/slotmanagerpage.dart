import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import 'features/slot_write_tag.dart';

class SlotManagerPage extends StatefulWidget {
  const SlotManagerPage({super.key});

  @override
  SlotManagerPageState createState() => SlotManagerPageState();
}

class SlotManagerPageState extends State<SlotManagerPage> {
  List<(ChameleonTag, ChameleonTag)> usedSlots = List.generate(
    8,
    (_) => (ChameleonTag.unknown, ChameleonTag.unknown),
  );

  List<Map<String, String>> slotData = List.generate(
    8,
    (_) => {
      'hfName': 'Loading',
      'lfName': 'Loading',
      'Last-updated': 'Not implemented',
    },
  );

  int currentFunctionIndex = 0;
  int progress = -1;

  Future<void> executeNextFunction() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    if (currentFunctionIndex == 0) {
      try {
        usedSlots = await connection.getUsedSlots();
      } catch (_) {}
    }
    if (currentFunctionIndex < 8) {
      try {
        slotData[currentFunctionIndex]['hfName'] = await connection
            .getSlotTagName(currentFunctionIndex, ChameleonTagFrequency.hf);
      } catch (_) {
        slotData[currentFunctionIndex]['hfName'] = "";
      }

      try {
        slotData[currentFunctionIndex]['lfName'] = await connection
            .getSlotTagName(currentFunctionIndex, ChameleonTagFrequency.lf);
      } catch (_) {
        slotData[currentFunctionIndex]['lfName'] = "";
      }

      if (slotData[currentFunctionIndex]['hfName']!.isEmpty) {
        slotData[currentFunctionIndex]['hfName'] = "Empty";
      }

      if (slotData[currentFunctionIndex]['lfName']!.isEmpty) {
        slotData[currentFunctionIndex]['lfName'] = "Empty";
      }

      setState(() {
        currentFunctionIndex++;
      });
    }
  }

  void reloadPage() {
    setUploadState(-1);
    setState(() {
      currentFunctionIndex = 0;
    });
    var appState = context.read<MyAppState>();
    appState.changesMade();
  }

  void setUploadState(int progressBar) {
    setState(() {
      progress = progressBar;
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
                      crossAxisCount: calculateCrossAxisCount(),
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
                                      Text(
                                          "${slotData[index]['hfName'] ?? "Unknown"} (${usedSlots[index].$1.name})")
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.wifi),
                                      const SizedBox(width: 5),
                                      Text(
                                          "${slotData[index]['lfName'] ?? "Unknown"} (${usedSlots[index].$2.name})")
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
            ),
            LinearProgressIndicator(
              value: (progress / 100).toDouble(),
              semanticsLabel: 'Linear progress indicator',
            )
          ],
        ),
      ),
    );
  }

  Future<String?> cardSelectDialog(BuildContext context, int gridPosition) {
    var appState = context.read<MyAppState>();
    var tags = appState.sharedPreferencesProvider.getChameleonTags();

    // Don't allow user to upload more tags while already uploading dump
    if (progress != -1) {
      return Future.value("");
    }

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate:
          CardSearchDelegate(tags, gridPosition, reloadPage, setUploadState),
    );
  }
}

class CardSearchDelegate extends SearchDelegate<String> {
  final List<ChameleonTagSave> cards;
  final int gridPosition;
  final dynamic refresh;
  final dynamic setUploadState;

  CardSearchDelegate(
      this.cards, this.gridPosition, this.refresh, this.setUploadState);

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
        card.tag.name
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
                subtitle: Text(card.tag.name),
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
        card.tag.name
            .toLowerCase()
            .contains(query.toLowerCase()));
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return ListTile(
          leading: Icon(card.tag.frequency == ChameleonTagFrequency.hf ? Icons.credit_card : Icons.wifi),
          title: Text(card.name),
          subtitle: Text(card.tag.name),
          onTap: () async {
            close(context, card.name);

            if (!card.tag.writable) {
              appState.log.e("Can't write this card type yet.");
              return;
            }

            final success = await slotWriteTag(
              card: card,
              connection: connection,
              slotIndex: gridPosition,
              onProgress: (progress) => setUploadState(progress),
            );
            if (success) {
              appState.changesMade();
              refresh();
            }
          },
        );
      },
    );
  }
}
