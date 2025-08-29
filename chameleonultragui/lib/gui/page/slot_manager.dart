import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/card_list.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/slot_settings.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class SlotManagerPage extends StatefulWidget {
  const SlotManagerPage({super.key});

  @override
  SlotManagerPageState createState() => SlotManagerPageState();
}

class SlotManagerPageState extends State<SlotManagerPage> {
  List<SlotTypes> usedSlots = List.generate(
    8,
    (_) => SlotTypes(),
  );

  List<EnabledSlotInfo> enabledSlots = List.generate(
    8,
    (_) => EnabledSlotInfo(),
  );

  List<SlotNames> slotData = List.generate(
    8,
    (_) => SlotNames(),
  );

  int progress = -1;
  int gridPosition = 0;
  bool onlyOneSlot = false;

  Future<void> loadSlotData() async {
    if (progress != -1) {
      return;
    }

    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    usedSlots = await appState.communicator!.getSlotTagTypes();
    enabledSlots = await appState.communicator!.getEnabledSlots();
    slotData = await appState.communicator!.getSlotTagNames();

    for (SlotNames slot in slotData) {
      slot.hf = slot.hf.isEmpty ? localizations.no_name : slot.hf;
      slot.lf = slot.lf.isEmpty ? localizations.no_name : slot.lf;
    }
  }

  void refreshSlot() {
    setUploadState(-1);

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

  Future<void> onTap(CardSave card, dynamic close) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    if (isMifareClassic(card.tag)) {
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
          uid: hexToBytes(card.uid),
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

        if (card.data.length > blockOffset &&
            card.data[blockOffset].length == 16) {
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
      refreshSlot();
    } else if (isEM410X(card.tag)) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!
          .enableSlot(gridPosition, TagFrequency.lf, true);
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setEM410XEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
          gridPosition,
          (card.name.isEmpty) ? localizations.no_name : card.name,
          TagFrequency.lf);
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.hidProx) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!
          .enableSlot(gridPosition, TagFrequency.lf, true);
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setHIDProxEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
          gridPosition,
          (card.name.isEmpty) ? localizations.no_name : card.name,
          TagFrequency.lf);
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (card.tag == TagType.viking) {
      close(context, card.name);
      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!
          .enableSlot(gridPosition, TagFrequency.lf, true);
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      await appState.communicator!.setVikingEmulatorID(hexToBytes(card.uid));
      await appState.communicator!.setSlotTagName(
          gridPosition,
          (card.name.isEmpty) ? localizations.no_name : card.name,
          TagFrequency.lf);
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else if (isMifareUltralight(card.tag)) {
      close(context, card.name);
      setUploadState(0);

      await appState.communicator!.setReaderDeviceMode(false);
      await appState.communicator!
          .enableSlot(gridPosition, TagFrequency.hf, true);
      await appState.communicator!.activateSlot(gridPosition);
      await appState.communicator!.setSlotType(gridPosition, card.tag);
      await appState.communicator!.setDefaultDataToSlot(gridPosition, card.tag);
      var cardData = CardData(
          uid: hexToBytes(card.uid),
          atqa: card.atqa,
          sak: card.sak,
          ats: card.ats);
      await appState.communicator!.setMf1AntiCollision(cardData);

      for (var page = 0;
          page < mfUltralightGetPagesCount(card.tag) && card.data.length > page;
          page++) {
        await appState.communicator!
            .mf0EmulatorWritePages(page, card.data[page]);

        setUploadState(
            (page / mfUltralightGetPagesCount(card.tag) * 100).round());

        await asyncSleep(1);
      }

      if (card.extraData.ultralightVersion.isNotEmpty) {
        await appState.communicator!
            .mf0EmulatorSetVersionData(card.extraData.ultralightVersion);
      }

      if (card.extraData.ultralightSignature.isNotEmpty) {
        await appState.communicator!
            .mf0EmulatorSetSignatureData(card.extraData.ultralightSignature);
      }

      if (card.extraData.ultralightCounters.isNotEmpty) {
        for (int i = 0; i < card.extraData.ultralightCounters.length; i++) {
          await appState.communicator!.mf0EmulatorSetCounterData(
              i, card.extraData.ultralightCounters[i], true);
        }
      }

      if (mfUltralightHasCounters(card.tag)) {
        await appState.communicator!.mf0ResetAuthCount();
      }

      setUploadState(100);

      await appState.communicator!.setSlotTagName(
          gridPosition,
          (card.name.isEmpty) ? localizations.no_name : card.name,
          TagFrequency.hf);
      await appState.communicator!.saveSlotData();
      appState.changesMade();
      refreshSlot();
    } else {
      appState.log!.e("Can't write this card type yet.");
      close(context, card.name);
    }
  }

  Future<String?> cardSelectDialog(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var tags = appState.sharedPreferencesProvider.getCards();

    // Don't allow user to upload more tags while already uploading dump
    if (progress != -1) {
      return Future.value("");
    }

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(cards: tags, onTap: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
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
              future: loadSlotData(),
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    progress != -1) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  appState.connector!.performDisconnect();
                  return ErrorPage(errorMessage: snapshot.error.toString());
                } else {
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
                                setState(() {
                                  gridPosition = index;
                                });
                                cardSelectDialog(context);
                              },
                              style: ButtonStyle(
                                shape: WidgetStateProperty.all<
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
                                            color: enabledSlots[index].any()
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.credit_card),
                                        const SizedBox(width: 5),
                                        Expanded(
                                            child: Text(
                                          "${slotData[index].hf} (${chameleonTagToString(usedSlots[index].hf, localizations)})",
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
                                                "${slotData[index].lf} (${chameleonTagToString(usedSlots[index].lf, localizations)})",
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: true,
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
                }
              },
            ),
            if (progress != -1) ...[
              const SizedBox(height: 32),
              Text(localizations.uploading_dump),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: (progress / 100).toDouble(),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
