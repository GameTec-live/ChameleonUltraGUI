import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/menu/card_edit.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CardViewMenu extends StatefulWidget {
  final CardSave tagSave;

  const CardViewMenu({Key? key, required this.tagSave}) : super(key: key);

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
      content: Column(
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
          ...(chameleonTagToFrequency(widget.tagSave.tag) == TagFrequency.hf)
              ? [
                  Row(
                    children: [
                      Text(
                          "${localizations.sak}: ${widget.tagSave.sak == 0 ? localizations.unavailable : bytesToHex(u8ToBytes(widget.tagSave.sak))}"),
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
                  )
                ]
              : [],
        ],
      ),
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
            var tags = appState.sharedPreferencesProvider.getCards();
            List<CardSave> output = [];
            for (var tagTest in tags) {
              if (tagTest.id != widget.tagSave.id) {
                output.add(tagTest);
              }
            }
            appState.sharedPreferencesProvider.setCards(output);
            appState.changesMade();
            Navigator.pop(context);
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
