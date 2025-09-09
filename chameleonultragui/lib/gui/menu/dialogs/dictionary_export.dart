import 'dart:convert';
import 'dart:io';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary_edit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class DictionaryExportMenu extends StatefulWidget {
  final String defaultName;
  final List<Uint8List> keys;

  const DictionaryExportMenu(
      {super.key, this.defaultName = "", required this.keys});

  @override
  DictionaryExportMenuState createState() => DictionaryExportMenuState();
}

class DictionaryExportMenuState extends State<DictionaryExportMenu> {
  List<Uint8List> deduplicateKeys(List<Uint8List> keys) {
    return <int, Uint8List>{
      for (var key in keys.where((key) => key.isNotEmpty).toList())
        Object.hashAll(key): key
    }.values.toList();
  }

  String convertKeysToDictionaryFile(List<Uint8List> keys) {
    List<Uint8List> deduplicatedKeys = deduplicateKeys(keys);
    String fileContents = "";

    for (Uint8List key in deduplicatedKeys) {
      fileContents += "${bytesToHex(key).toUpperCase()}\n";
    }

    return fileContents.trim();
  }

  Future<String?> dictionarySelectDialog(
      BuildContext context, List<Uint8List> keys) {
    var appState = context.read<ChameleonGUIState>();
    var dicts = appState.sharedPreferencesProvider.getDictionaries();

    dicts.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: DictSearchDelegate(dicts, keys),
    );
  }

  Future<String> getDictionaryName() async {
    var localizations = AppLocalizations.of(context)!;
    TextEditingController dictionary =
        TextEditingController(text: widget.defaultName);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(localizations.enter_name_of_dictionary),
          content: TextField(
            controller: dictionary,
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Text(localizations.ok),
            ),
            ElevatedButton(
              onPressed: () {
                dictionary.text = "";
                Navigator.pop(context);
              },
              child: Text(localizations.cancel),
            ),
          ],
        );
      },
    );

    return dictionary.text;
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.save_recovered_keys),
      content: Text(localizations.save_recovered_keys_where),
      actions: [
        ElevatedButton(
          onPressed: () async {
            String fileContents = convertKeysToDictionaryFile(widget.keys);
            String name = await getDictionaryName();
            if (name.isEmpty) {
              if (context.mounted) {
                Navigator.pop(context);
              }

              return;
            }

            try {
              await FileSaver.instance.saveAs(
                  name: name,
                  bytes: const Utf8Encoder().convert(fileContents),
                  ext: 'dic',
                  mimeType: MimeType.other);
            } on UnimplementedError catch (_) {
              String? outputFile = await FilePicker.platform.saveFile(
                dialogTitle: '${localizations.output_file}:',
                fileName: '$name.dic',
              );
              if (outputFile != null) {
                var file = File(outputFile);
                await file
                    .writeAsBytes(const Utf8Encoder().convert(fileContents));
              }
            }
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(localizations.save_recovered_keys_to_file),
        ),
        ElevatedButton(
          onPressed: () async {
            await dictionarySelectDialog(context, deduplicateKeys(widget.keys));
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(localizations.add_recovered_keys_to_existing_dict),
        ),
        ElevatedButton(
          onPressed: () async {
            String name = await getDictionaryName();
            if (name.isEmpty) {
              if (context.mounted) {
                Navigator.pop(context);
              }

              return;
            }

            Dictionary dictionary = Dictionary(
              name: name,
              color: Colors.blue,
              keys: deduplicateKeys(widget.keys),
            );

            if (context.mounted) {
              await showDialog<String>(
                context: context,
                builder: (BuildContext context) {
                  return DictionaryEditMenu(
                      dictionary: dictionary, isNew: true);
                },
              );
              if (context.mounted) {
                Navigator.pop(context);
              }
            }
          },
          child: Text(localizations.create_new_dict_with_recovered_keys),
        ),
      ],
    );
  }
}

class DictSearchDelegate extends SearchDelegate<String> {
  final List<Dictionary> dicts;
  final List<Uint8List> keys;

  DictSearchDelegate(this.dicts, this.keys);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
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
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        return ListTile(
          leading: Icon(Icons.key, color: dict.color),
          title: Text(dict.name),
          subtitle: Text("${dict.keys.length.toString()} keys"),
          onTap: () async {},
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));

    var appState = context.read<ChameleonGUIState>();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        return ListTile(
          leading: Icon(Icons.key, color: dict.color),
          title: Text(dict.name),
          subtitle: Text("${dict.keys.length.toString()} keys"),
          onTap: () async {
            dict.keys.addAll(keys);
            appState.sharedPreferencesProvider.setDictionaries(dicts);
            appState.changesMade();
            Navigator.pop(context);
          },
        );
      },
    );
  }
}
