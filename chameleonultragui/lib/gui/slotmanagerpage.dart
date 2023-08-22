import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/components/slotsettings.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
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

  List<bool> enabledSlots = List.generate(
    8,
    (_) => true,
  );

  List<Map<String, String>> slotData = List.generate(
    8,
    (_) => {
      'hfName': '...',
      'lfName': '...',
    },
  );

  int currentFunctionIndex = 0;
  int progress = -1;
  bool onlyOneSlot = false;

  Future<void> executeNextFunction() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    if (currentFunctionIndex == 0 || onlyOneSlot) {
      try {
        usedSlots = await connection.getUsedSlots();
      } catch (_) {}
    }
    if (currentFunctionIndex == 0 || onlyOneSlot) {
      try {
        enabledSlots = await connection.getEnabledSlots();
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
      if (!onlyOneSlot) {
        setState(() {
          currentFunctionIndex++;
        });
      } else {
        setState(() {
          currentFunctionIndex = 8;
        });
      }
    }
  }

  void refreshSlot(int slot) {
    setUploadState(-1);
    setState(() {
      currentFunctionIndex = slot;
      onlyOneSlot = true;
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
                              padding: const EdgeInsets.only(
                                  top: 8.0, left: 8.0, bottom: 8.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.nfc,
                                          color: enabledSlots[index]
                                              ? Colors.green
                                              : Colors.deepOrange),
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
                                    children: [
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.wifi),
                                            const SizedBox(width: 5),
                                            Text(
                                              "${slotData[index]['lfName'] ?? "Unknown"} (${usedSlots[index].$2.name})",
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (BuildContext context) {
                                              return SlotSettings(
                                                  slot: index,
                                                  refresh: refreshSlot);
                                            },
                                          );
                                        },
                                        icon: const Icon(Icons.settings),
                                      ),
                                    ],
                                  )
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
          CardSearchDelegate(tags, gridPosition, refreshSlot, setUploadState),
    );
  }
}

enum SearchFilter { all, hf, lf }

class CardSearchDelegate extends SearchDelegate<String> {
  final List<ChameleonTagSave> cards;
  final int gridPosition;
  final dynamic refresh;
  final dynamic setUploadState;
  SearchFilter filter = SearchFilter.all;

  CardSearchDelegate(
      this.cards, this.gridPosition, this.refresh, this.setUploadState);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return DropdownButton(
            items: const [
              DropdownMenuItem(
                value: SearchFilter.all,
                child: Text("All"),
              ),
              DropdownMenuItem(
                value: SearchFilter.hf,
                child: Text("HF"),
              ),
              DropdownMenuItem(
                value: SearchFilter.lf,
                child: Text("LF"),
              ),
            ],
            onChanged: (SearchFilter? value) {
              if (value != null) {
                setState(() {
                  filter = value;
                });
              }
            },
            value: filter,
          );
        },
      ),
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
        (((card.name.toLowerCase().contains(query.toLowerCase())) ||
                (card.tag.name
                    .toLowerCase()
                    .contains(query.toLowerCase()))) &&
            ((filter == SearchFilter.all) ||
                (filter == SearchFilter.hf &&
                    card.tag.frequency ==
                        ChameleonTagFrequency.hf) ||
                (filter == SearchFilter.lf &&
                    card.tag.frequency ==
                        ChameleonTagFrequency.lf))));

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
        (((card.name.toLowerCase().contains(query.toLowerCase())) ||
                (card.tag.name
                    .toLowerCase()
                    .contains(query.toLowerCase()))) &&
            ((filter == SearchFilter.all) ||
                (filter == SearchFilter.hf &&
                    card.tag.frequency ==
                        ChameleonTagFrequency.hf) ||
                (filter == SearchFilter.lf &&
                    card.tag.frequency ==
                        ChameleonTagFrequency.lf))));

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
              refresh(gridPosition);
            }
          },
        );
      },
    );
  }
}
