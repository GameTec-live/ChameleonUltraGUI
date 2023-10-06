import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/gui/menu/card_edit.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SaveEditMenu extends StatefulWidget {
  final CardSave tagSave;

  const SaveEditMenu({Key? key, required this.tagSave}) : super(key: key);

  @override
  SaveEditMenuState createState() => SaveEditMenuState();
}

class SaveEditMenuState extends State<SaveEditMenu> {
  Future<void> saveTag(
      CardSave tag, ChameleonGUIState appState, bool bin) async {
    var localizations = AppLocalizations.of(context)!;
    if (bin) {
      List<int> tagDump = [];
      for (var block in tag.data) {
        tagDump.addAll(block);
      }
      try {
        await FileSaver.instance.saveAs(
            name: tag.name,
            bytes: Uint8List.fromList(tagDump),
            ext: 'bin',
            mimeType: MimeType.other);
      } on UnimplementedError catch (_) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '${localizations.output_file}:',
          fileName: '${tag.name}.bin',
        );

        if (outputFile != null) {
          var file = File(outputFile);
          await file.writeAsBytes(Uint8List.fromList(tagDump));
        }
      }
    } else {
      try {
        await FileSaver.instance.saveAs(
            name: tag.name,
            bytes: const Utf8Encoder().convert(tag.toJson()),
            ext: 'json',
            mimeType: MimeType.other);
      } on UnimplementedError catch (_) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '${localizations.output_file}:',
          fileName: '${tag.name}.json',
        );

        if (outputFile != null) {
          var file = File(outputFile);
          await file.writeAsBytes(const Utf8Encoder().convert(tag.toJson()));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();

    return AlertDialog(
      title: Expanded(
          child: Text(widget.tagSave.name,
              maxLines: 3, overflow: TextOverflow.ellipsis)),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text("${localizations.uid}: ${widget.tagSave.uid}"),
          Text(
              "${localizations.tag_type}: ${chameleonTagToString(widget.tagSave.tag)}"),
          Text(
              "${localizations.sak}: ${widget.tagSave.sak == 0 ? localizations.unavailable : bytesToHex(u8ToBytes(widget.tagSave.sak))}"),
          Text(
              "${localizations.atqa}: ${widget.tagSave.atqa.asMap().containsKey(0) ? bytesToHex(u8ToBytes(widget.tagSave.atqa[0])) : ""} ${widget.tagSave.atqa.asMap().containsKey(1) ? bytesToHex(u8ToBytes(widget.tagSave.atqa[1])) : localizations.unavailable}"),
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
                          await saveTag(widget.tagSave, appState, true);
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        child: Text(localizations.save_as(".bin")),
                      ),
                    ElevatedButton(
                      onPressed: () async {
                        await saveTag(widget.tagSave, appState, false);
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
