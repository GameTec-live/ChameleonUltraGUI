import 'dart:io';

import 'package:chameleonultragui/gui/menu/dictionary_edit.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:chameleonultragui/gui/menu/confirm_delete.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class DictionaryViewMenu extends StatefulWidget {
  final Dictionary dictionary;

  const DictionaryViewMenu({super.key, required this.dictionary});

  @override
  DictionaryViewMenuState createState() => DictionaryViewMenuState();
}

class DictionaryViewMenuState extends State<DictionaryViewMenu> {
  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();

    String output = "";
    for (var key in widget.dictionary.keys) {
      output += "${bytesToHex(key)}\n".toUpperCase();
    }
    output.trim();

    return AlertDialog(
      title: Text(widget.dictionary.name,
          maxLines: 3, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                  "${localizations.key_count}: ${widget.dictionary.keys.length}"),
              IconButton(
                onPressed: () async {
                  ClipboardData data = ClipboardData(
                      text: widget.dictionary.keys.length.toString());
                  await Clipboard.setData(data);
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            width: MediaQuery.of(context).size.width < 600
                ? MediaQuery.of(context).size.width
                : MediaQuery.of(context).size.width * 0.5,
            child: ListView(
              children: [
                Text(
                  output,
                  style:
                      const TextStyle(fontFamily: 'RobotoMono', fontSize: 16.0),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              ClipboardData data = ClipboardData(text: output);
              await Clipboard.setData(data);
            },
            child: Row(
              children: [
                Text(localizations.copy_all_keys),
                const Icon(Icons.copy),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return DictionaryEditMenu(dictionary: widget.dictionary);
              },
            );
          },
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          onPressed: () async {
            try {
              await FileSaver.instance.saveAs(
                  name: widget.dictionary.name,
                  bytes: widget.dictionary.toFile(),
                  ext: 'dic',
                  mimeType: MimeType.other);
            } on UnimplementedError catch (_) {
              String? outputFile = await FilePicker.platform.saveFile(
                dialogTitle: '${localizations.output_file}:',
                fileName: '${widget.dictionary.name}.dic',
              );

              if (outputFile != null) {
                var file = File(outputFile);
                await file.writeAsBytes(widget.dictionary.toFile());
              }
            }
          },
          icon: const Icon(Icons.download),
        ),
        IconButton(
          onPressed: () async {
            if (appState.sharedPreferencesProvider.getConfirmDelete() == true) {
              var confirm = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ConfirmDeletionMenu(
                      thingBeingDeleted: widget.dictionary.name);
                },
              );

              if (confirm != true) {
                return;
              }
            }
            var dictionaries =
                appState.sharedPreferencesProvider.getDictionaries();
            List<Dictionary> output = [];
            for (var dict in dictionaries) {
              if (dict.id != widget.dictionary.id) {
                output.add(dict);
              }
            }
            appState.sharedPreferencesProvider.setDictionaries(output);
            appState.changesMade();
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}
