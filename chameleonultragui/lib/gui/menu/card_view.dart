import 'package:chameleonultragui/gui/menu/card_edit.dart';
import 'package:chameleonultragui/gui/menu/dictionary_export.dart';
import 'package:chameleonultragui/gui/menu/dump_editor.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/services.dart';
import 'package:chameleonultragui/gui/menu/confirm_delete.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class CardViewMenu extends StatefulWidget {
  final CardSave tagSave;

  const CardViewMenu({super.key, required this.tagSave});

  @override
  CardViewMenuState createState() => CardViewMenuState();
}

class CardViewMenuState extends State<CardViewMenu> {
  late CardSave currentSavedCard;
  String uid = '';

  @override
  void initState() {
    super.initState();
    currentSavedCard = widget.tagSave;
    if (chameleonTagToFrequency(currentSavedCard.tag) == TagFrequency.lf) {
      LFCard card =
          getLFCardFromUID(currentSavedCard.tag, currentSavedCard.uid);
      uid = card.toViewableString();
    } else {
      uid = currentSavedCard.uid;
    }
  }

  void _refreshCardData() {
    var appState = context.read<ChameleonGUIState>();
    var cards = appState.sharedPreferencesProvider.getCards();
    var updatedCard = cards.firstWhere(
      (card) => card.id == widget.tagSave.id,
      orElse: () => widget.tagSave,
    );

    if (chameleonTagToFrequency(updatedCard.tag) == TagFrequency.lf) {
      LFCard card = getLFCardFromUID(updatedCard.tag, updatedCard.uid);
      uid = card.toViewableString();
    } else {
      uid = updatedCard.uid;
    }

    setState(() {
      currentSavedCard = updatedCard;
    });
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();

    return AlertDialog(
      title: Text(currentSavedCard.name,
          maxLines: 3, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "${localizations.uid}: $uid",
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
              IconButton(
                onPressed: () async {
                  ClipboardData data =
                      ClipboardData(text: currentSavedCard.uid);
                  await Clipboard.setData(data);
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  "${localizations.tag_type}: ${chameleonTagToString(currentSavedCard.tag, localizations)}",
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
              IconButton(
                onPressed: () async {
                  ClipboardData data = ClipboardData(
                      text: chameleonTagToString(
                          currentSavedCard.tag, localizations));
                  await Clipboard.setData(data);
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          if (chameleonTagToFrequency(currentSavedCard.tag) ==
              TagFrequency.hf) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${localizations.sak}: ${bytesToHex(u8ToBytes(currentSavedCard.sak))}",
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    ClipboardData data = ClipboardData(
                        text: currentSavedCard.sak == 0
                            ? localizations.unavailable
                            : bytesToHex(u8ToBytes(currentSavedCard.sak)));
                    await Clipboard.setData(data);
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${localizations.atqa}: ${currentSavedCard.atqa.isNotEmpty ? bytesToHexSpace(currentSavedCard.atqa) : localizations.unavailable}",
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    ClipboardData data = ClipboardData(
                        text: currentSavedCard.atqa.isNotEmpty
                            ? bytesToHex(currentSavedCard.atqa)
                            : localizations.unavailable);
                    await Clipboard.setData(data);
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            if (isMifareClassic(currentSavedCard.tag))
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed:
                          (mfClassicGetKeysFromDump(currentSavedCard.data)
                                  .isNotEmpty)
                              ? () async {
                                  List<Uint8List> keys =
                                      mfClassicGetKeysFromDump(
                                          currentSavedCard.data);
                                  await showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return DictionaryExportMenu(keys: keys);
                                    },
                                  );
                                }
                              : null,
                      child: Text(localizations.export_to_dictionary)),
                ],
              ),
            if (isMifareUltralight(currentSavedCard.tag))
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${localizations.ultralight_version}: ${currentSavedCard.extraData.ultralightVersion.isNotEmpty ? bytesToHexSpace(currentSavedCard.extraData.ultralightVersion) : localizations.unavailable}",
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        ClipboardData data = ClipboardData(
                            text: currentSavedCard
                                    .extraData.ultralightVersion.isNotEmpty
                                ? bytesToHexSpace(currentSavedCard
                                    .extraData.ultralightVersion)
                                : localizations.unavailable);
                        await Clipboard.setData(data);
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${localizations.ultralight_signature}: ${currentSavedCard.extraData.ultralightSignature.isNotEmpty ? bytesToHexSpace(currentSavedCard.extraData.ultralightSignature) : localizations.unavailable}",
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        ClipboardData data = ClipboardData(
                            text: currentSavedCard
                                    .extraData.ultralightSignature.isNotEmpty
                                ? bytesToHexSpace(currentSavedCard
                                    .extraData.ultralightSignature)
                                : localizations.unavailable);
                        await Clipboard.setData(data);
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ])
          ],
        ],
      )),
      actions: [
        Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              IconButton(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return CardEditMenu(tagSave: currentSavedCard);
                    },
                  );
                  _refreshCardData();
                },
                icon: const Icon(Icons.edit),
              ),
              if (isMifareClassic(widget.tagSave.tag) ||
                  isMifareUltralight(widget.tagSave.tag))
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DumpEditor(
                          cardSave: widget.tagSave,
                          onSave: (dumpData) {
                            // Update card data
                            var updatedCard = CardSave(
                              id: widget.tagSave.id,
                              uid: widget.tagSave.uid,
                              sak: widget.tagSave.sak,
                              atqa: widget.tagSave.atqa,
                              name: widget.tagSave.name,
                              tag: widget.tagSave.tag,
                              data: dumpData,
                              ats: widget.tagSave.ats,
                              extraData: widget.tagSave.extraData,
                            );

                            // Update the card in storage
                            var cards =
                                appState.sharedPreferencesProvider.getCards();
                            for (int i = 0; i < cards.length; i++) {
                              if (cards[i].id == widget.tagSave.id) {
                                cards[i] = updatedCard;
                                break;
                              }
                            }
                            appState.sharedPreferencesProvider.setCards(cards);
                            appState.changesMade();
                            Navigator.pop(
                                context); // Close the card view dialog
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_document),
                ),
              IconButton(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text(localizations.select_save_format),
                        actions: [
                          if (isMifareClassic(currentSavedCard.tag))
                            ElevatedButton(
                              onPressed: () async {
                                await saveTag(currentSavedCard, context, true);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              child: Text(localizations.save_as(".bin")),
                            ),
                          ElevatedButton(
                            onPressed: () async {
                              await saveTag(currentSavedCard, context, false);
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: Text(localizations.save_as(".json")),
                          ),
                        ],
                      );
                    },
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.download_rounded),
              ),
              IconButton(
                onPressed: () async {
                  if (appState.sharedPreferencesProvider.getConfirmDelete() ==
                      true) {
                    var confirm = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return ConfirmDeletionMenu(
                            thingBeingDeleted: currentSavedCard.name);
                      },
                    );

                    if (confirm != true) {
                      return;
                    }
                  }
                  var tags = appState.sharedPreferencesProvider.getCards();
                  List<CardSave> output = [];
                  for (var tagTest in tags) {
                    if (tagTest.id != currentSavedCard.id) {
                      output.add(tagTest);
                    }
                  }
                  appState.sharedPreferencesProvider.setCards(output);
                  appState.changesMade();
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.delete_outline),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(localizations.ok),
              ),
            ]),
      ],
    );
  }
}
