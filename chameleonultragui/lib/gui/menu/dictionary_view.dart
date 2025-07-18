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

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class DictionaryViewMenu extends StatefulWidget {
  final Dictionary dictionary;

  const DictionaryViewMenu({super.key, required this.dictionary});

  @override
  DictionaryViewMenuState createState() => DictionaryViewMenuState();
}

class DictionaryViewMenuState extends State<DictionaryViewMenu> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();

    String output = widget.dictionary.keys
        .map((key) => bytesToHex(key).toUpperCase())
        .join('\n');

    return AlertDialog(
      title: Text(
        widget.dictionary.name,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width < 600
            ? MediaQuery.of(context).size.width * 0.9
            : MediaQuery.of(context).size.width * 0.5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${localizations.key_count}: ${widget.dictionary.keys.length}",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: widget.dictionary.keys.length.toString(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16.0),
                          child: SelectableText(
                            output,
                            style: const TextStyle(
                              fontFamily: 'RobotoMono',
                              fontSize: 16.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: output));
                        },
                        icon: const Icon(Icons.copy),
                        label: Text(localizations.copy_all_keys),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                mimeType: MimeType.other,
              );
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
                    thingBeingDeleted: widget.dictionary.name,
                  );
                },
              );

              if (confirm != true) {
                return;
              }
            }

            var dictionaries =
                appState.sharedPreferencesProvider.getDictionaries();
            var updatedDictionaries = dictionaries
                .where((dict) => dict.id != widget.dictionary.id)
                .toList();

            appState.sharedPreferencesProvider
                .setDictionaries(updatedDictionaries);
            appState.changesMade();
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}
