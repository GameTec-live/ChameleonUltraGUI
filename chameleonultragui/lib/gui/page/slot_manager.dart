import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/features/slot_write_tag.dart';
import 'package:chameleonultragui/gui/menu/slot_settings.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
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
  List<(TagType, TagType)> usedSlots = List.generate(
    8,
    (_) => (TagType.unknown, TagType.unknown),
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

    if (currentFunctionIndex == 0 || onlyOneSlot) {
      try {
        usedSlots = await appState.communicator!.getUsedSlots();
      } catch (_) {
        try {
          await appState.communicator!.getFirmwareVersion();
        } catch (_) {
          appState.log.e("Lost connection to Chameleon!");
          await appState.connector.performDisconnect();
          appState.changesMade();
        }
      }
      try {
        enabledSlots = await appState.communicator!.getEnabledSlots();
      } catch (_) {}
    }

    if (currentFunctionIndex < 8) {
      slotData[currentFunctionIndex]['hfName'] = "";
      slotData[currentFunctionIndex]['lfName'] = "";

      for (var i = 0; i < 2; i++) {
        try {
          slotData[currentFunctionIndex]['hfName'] = await appState
              .communicator!
              .getSlotTagName(currentFunctionIndex, TagFrequency.hf);
          break;
        } catch (_) {}
      }

      if (slotData[currentFunctionIndex]['hfName']!.isEmpty) {
        slotData[currentFunctionIndex]['hfName'] = "Empty";
      }

      for (var i = 0; i < 2; i++) {
        try {
          slotData[currentFunctionIndex]['lfName'] = await appState
              .communicator!
              .getSlotTagName(currentFunctionIndex, TagFrequency.lf);
          break;
        } catch (_) {}
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
          // Reset onlyOneSlot to prevent getting used slots & fw version
          // on every appState.changesMade 
          onlyOneSlot = false;
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
  }

  void setUploadState(int progressBar) {
    setState(() {
      progress = progressBar;
    });

    // No need to call appState.changesMade as progress bar will already update and
    // the combination of
    // - the calls to appState.changesMade both here as in refreshSlot
    // - the onlyOneSlot not being reset after executeNextFunction finished caused
    // caused issues with the SerialPort on web as every progress bar update was
    // forcibly refreshing the ui and calling getUsedSlots/ getFwVersion
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
                  child: StaggeredGridView.countBuilder(
                    padding: const EdgeInsets.all(20),
                    crossAxisCount:
                        MediaQuery.of(context).size.width >= 600 ? 2 : 1,
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
                                top: 8.0, left: 8.0, bottom: 6.0),
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
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    staggeredTileBuilder: (int index) =>
                        const StaggeredTile.fit(1),
                  ),
                );
              },
            ),
            if (progress != -1)
              LinearProgressIndicator(
                value: (progress / 100).toDouble(),
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
  final List<TagSave> cards;
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
                    card.tag.frequency == TagFrequency.hf) ||
                (filter == SearchFilter.lf &&
                    card.tag.frequency == TagFrequency.lf))));

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
                    card.tag.frequency == TagFrequency.hf) ||
                (filter == SearchFilter.lf &&
                    card.tag.frequency == TagFrequency.lf))));

    var appState = context.read<MyAppState>();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return ListTile(
          leading: Icon(card.tag.frequency == TagFrequency.hf ? Icons.credit_card : Icons.wifi),
          title: Text(card.name),
          subtitle: Text(card.tag.name +
              ((chameleonTagSaveCheckForMifareClassicEV1(card)) ? " EV1" : "")),
          onTap: () async {
            close(context, card.name);

            if (!card.tag.writable) {
              appState.log.e("Can't write this card type yet.");
              return;
            }

            final success = await slotWriteTag(
              card: card,
              communicator: appState.communicator!,
              slotIndex: gridPosition,
              onProgress: (progress) => setUploadState(progress),
            );
            if (success) {
              refresh(gridPosition);
            }
          }
        );
      },
    );
  }
}
