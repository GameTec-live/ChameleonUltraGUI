import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/card_list.dart';
import 'package:chameleonultragui/gui/menu/slot_settings.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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

  List<(bool, bool)> enabledSlots = List.generate(
    8,
    (_) => (true, true),
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
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    if (currentFunctionIndex == 0 || onlyOneSlot) {
      try {
        usedSlots = await appState.communicator!.getUsedSlots();
      } catch (_) {
        try {
          await appState.communicator!.getFirmwareVersion();
        } catch (_) {
          appState.log!.e("Lost connection to Chameleon!");
          appState.connector!.performDisconnect();
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
        slotData[currentFunctionIndex]['hfName'] = localizations.empty;
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
        slotData[currentFunctionIndex]['lfName'] = localizations.empty;
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
    var appState = context.read<ChameleonGUIState>();
    appState.changesMade();
  }

  void setUploadState(int progressBar) {
    setState(() {
      progress = progressBar;
    });
    var appState = context.read<ChameleonGUIState>();
    appState.changesMade();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.slot_manager),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            FutureBuilder(
              future: executeNextFunction(),
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                return Expanded(
                  child: AlignedGridView.count(
                      padding: const EdgeInsets.all(20),
                      crossAxisCount:
                          MediaQuery.of(context).size.width >= 700 ? 2 : 1,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      itemCount: 8,
                      itemBuilder: (BuildContext context, int index) {
                        return Container(
                          constraints: const BoxConstraints(
                              maxHeight: 160, minHeight: 100),
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
                                          color: enabledSlots[index].$1 ||
                                                  enabledSlots[index].$2
                                              ? Colors.green
                                              : Colors.deepOrange),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          "${localizations.slot} ${index + 1}",
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.credit_card),
                                      const SizedBox(width: 5),
                                      Expanded(
                                          child: Text(
                                        "${slotData[index]['hfName'] ?? localizations.unknown} (${chameleonTagToString(usedSlots[index].$1)})",
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ))
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
                                            Expanded(
                                                child: Text(
                                              "${slotData[index]['lfName'] ?? localizations.unknown} (${chameleonTagToString(usedSlots[index].$2)})",
                                              //maxLines: 2,
                                              overflow: TextOverflow.clip,
                                            ))
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
                      }),
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

  Future<void> onTap(CardSave card, int gridPosition, dynamic close) async {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    if ([
      TagType.mifareMini,
      TagType.mifare1K,
      TagType.mifare2K,
      TagType.mifare4K
    ].contains(card.tag)) {
      close(context, card.name);
      setUploadState(0);
      var isEV1 = chameleonTagSaveCheckForMifareClassicEV1(card);
      if (isEV1) {
        card.tag = TagType.mifare2K;
      }

      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!
          .enableSlot(gridPosition, TagFrequency.hf, true);
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      var cardData = CardData(
          uid: hexToBytes(card.uid.replaceAll(" ", "")),
          atqa: card.atqa,
          sak: card.sak,
          ats: card.ats);
      await appState.communicator!.setMf1AntiCollision(cardData);

      List<int> blockChunk = [];
      int lastSend = 0;

      for (var blockOffset = 0;
          blockOffset <
              mfClassicGetBlockCount(
                  chameleonTagTypeGetMfClassicType(card.tag));
          blockOffset++) {
        if ((card.data.length > blockOffset &&
                card.data[blockOffset].isEmpty) ||
            blockChunk.length >= 128) {
          if (blockChunk.isNotEmpty) {
            await appState.communicator!
                .setMf1BlockData(lastSend, Uint8List.fromList(blockChunk));
            blockChunk = [];
            lastSend = blockOffset;
          }
        }

        if (card.data.length > blockOffset) {
          blockChunk.addAll(card.data[blockOffset]);
        }

        setUploadState((blockOffset /
                mfClassicGetBlockCount(
                    chameleonTagTypeGetMfClassicType(card.tag)) *
                100)
            .round());
        await asyncSleep(1);
      }

      if (blockChunk.isNotEmpty) {
        await appState.communicator!
            .setMf1BlockData(lastSend, Uint8List.fromList(blockChunk));
      }

      setUploadState(100);

      await appState.communicator!.setSlotTagName(
          gridPosition,
          (card.name.isEmpty) ? localizations.no_name : card.name,
          TagFrequency.hf);
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot(gridPosition);
    } else if (card.tag == TagType.em410X) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!
          .enableSlot(gridPosition, TagFrequency.lf, true);
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!
          .setEM410XEmulatorID(hexToBytes(card.uid.replaceAll(" ", "")));
      await appState.communicator!.setSlotTagName(
          gridPosition,
          (card.name.isEmpty) ? localizations.no_name : card.name,
          TagFrequency.lf);
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot(gridPosition);
    } else {
      appState.log!.e("Can't write this card type yet.");
      close(context, card.name);
    }
  }

  Future<String?> cardSelectDialog(BuildContext context, int gridPosition) {
    var appState = context.read<ChameleonGUIState>();
    var tags = appState.sharedPreferencesProvider.getCards();

    // Don't allow user to upload more tags while already uploading dump
    if (progress != -1) {
      return Future.value("");
    }

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(tags, gridPosition, onTap),
    );
  }
}
