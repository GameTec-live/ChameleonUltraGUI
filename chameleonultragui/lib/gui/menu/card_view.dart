import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/menu/card_edit.dart';
import 'package:chameleonultragui/gui/menu/dictionary_export.dart';
import 'package:chameleonultragui/gui/menu/dump_editor.dart';
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
  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();

    return AlertDialog(
      title: Text(widget.tagSave.name,
          maxLines: 3, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("${localizations.uid}: ${widget.tagSave.uid}"),
              IconButton(
                onPressed: () async {
                  ClipboardData data = ClipboardData(text: widget.tagSave.uid);
                  await Clipboard.setData(data);
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                  "${localizations.tag_type}: ${chameleonTagToString(widget.tagSave.tag)}"),
              IconButton(
                onPressed: () async {
                  ClipboardData data = ClipboardData(
                      text: chameleonTagToString(widget.tagSave.tag));
                  await Clipboard.setData(data);
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          if (chameleonTagToFrequency(widget.tagSave.tag) ==
              TagFrequency.hf) ...[
            Row(
              children: [
                Text(
                    "${localizations.sak}: ${bytesToHex(u8ToBytes(widget.tagSave.sak))}"),
                IconButton(
                  onPressed: () async {
                    ClipboardData data = ClipboardData(
                        text: widget.tagSave.sak == 0
                            ? localizations.unavailable
                            : bytesToHex(u8ToBytes(widget.tagSave.sak)));
                    await Clipboard.setData(data);
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                    "${localizations.atqa}: ${widget.tagSave.atqa.isNotEmpty ? bytesToHexSpace(widget.tagSave.atqa) : localizations.unavailable}"),
                IconButton(
                  onPressed: () async {
                    ClipboardData data = ClipboardData(
                        text: widget.tagSave.atqa.isNotEmpty
                            ? bytesToHex(widget.tagSave.atqa)
                            : localizations.unavailable);
                    await Clipboard.setData(data);
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            if (isMifareClassic(widget.tagSave.tag))
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed: (mfClassicGetKeysFromDump(widget.tagSave.data)
                              .isNotEmpty)
                          ? () async {
                              List<Uint8List> keys =
                                  mfClassicGetKeysFromDump(widget.tagSave.data);
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
            if (isMifareUltralight(widget.tagSave.tag))
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(
                  children: [
                    Text(
                        "${localizations.ultralight_version}: ${widget.tagSave.extraData.ultralightVersion.isNotEmpty ? bytesToHexSpace(widget.tagSave.extraData.ultralightVersion) : localizations.unavailable}"),
                    IconButton(
                      onPressed: () async {
                        ClipboardData data = ClipboardData(
                            text: widget.tagSave.extraData.ultralightVersion
                                    .isNotEmpty
                                ? bytesToHexSpace(
                                    widget.tagSave.extraData.ultralightVersion)
                                : localizations.unavailable);
                        await Clipboard.setData(data);
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                        "${localizations.ultralight_signature}: ${widget.tagSave.extraData.ultralightSignature.isNotEmpty ? bytesToHexSpace(widget.tagSave.extraData.ultralightSignature) : localizations.unavailable}"),
                    IconButton(
                      onPressed: () async {
                        ClipboardData data = ClipboardData(
                            text: widget.tagSave.extraData.ultralightVersion
                                    .isNotEmpty
                                ? bytesToHexSpace(
                                    widget.tagSave.extraData.ultralightVersion)
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
        IconButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return CardEditMenu(tagSave: widget.tagSave);
              },
            );
          },
          icon: const Icon(Icons.edit),
        ),
        if (isMifareClassic(widget.tagSave.tag))
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
                      var cards = appState.sharedPreferencesProvider.getCards();
                      for (int i = 0; i < cards.length; i++) {
                        if (cards[i].id == widget.tagSave.id) {
                          cards[i] = updatedCard;
                          break;
                        }
                      }
                      appState.sharedPreferencesProvider.setCards(cards);
                      appState.changesMade();
                      Navigator.pop(context); // Close the card view dialog
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.edit_document),
            tooltip: 'Edit Dump',
          ),
        IconButton(
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(localizations.select_save_format),
                  actions: [
                    if (isMifareClassic(widget.tagSave.tag))
                      ElevatedButton(
                        onPressed: () async {
                          await saveTag(widget.tagSave, context, true);
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        child: Text(localizations.save_as(".bin")),
                      ),
                    ElevatedButton(
                      onPressed: () async {
                        await saveTag(widget.tagSave, context, false);
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
            if (appState.sharedPreferencesProvider.getConfirmDelete() == true) {
              var confirm = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ConfirmDeletionMenu(
                      thingBeingDeleted: widget.tagSave.name);
                },
              );

              if (confirm != true) {
                return;
              }
            }
            var tags = appState.sharedPreferencesProvider.getCards();
            List<CardSave> output = [];
            for (var tagTest in tags) {
              if (tagTest.id != widget.tagSave.id) {
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
      ],
    );
  }
}
