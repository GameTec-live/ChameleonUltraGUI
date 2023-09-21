import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/widget/staggered_grid_view.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:chameleonultragui/gui/menu/card_edit.dart';
import 'package:chameleonultragui/gui/menu/dictionary_edit.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SavedCardsPage extends StatefulWidget {
  const SavedCardsPage({super.key});

  @override
  SavedCardsPageState createState() => SavedCardsPageState();
}

class SavedCardsPageState extends State<SavedCardsPage> {
  MifareClassicType selectedType = MifareClassicType.m1k;

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

  // ignore_for_file: use_build_context_synchronously
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var dictionaries = appState.sharedPreferencesProvider.getDictionaries();
    var tags = appState.sharedPreferencesProvider.getCards();
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.saved_cards),
        systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Theme.of(context).colorScheme.surface),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "${localizations.cards}:",
                style: const TextStyle(fontSize: 20),
              ),
            ),
            Expanded(
              child: Card(
                child: StaggeredGridView.countBuilder(
                  padding: const EdgeInsets.all(20),
                  crossAxisCount:
                      MediaQuery.of(context).size.width >= 600 ? 2 : 1,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  itemCount: tags.length + 1,
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: ElevatedButton(
                          onPressed: () async {
                            FilePickerResult? result =
                                await FilePicker.platform.pickFiles();

                            if (result != null) {
                              File file = File(result.files.single.path!);
                              var contents = await file.readAsBytes();
                              try {
                                var string =
                                    const Utf8Decoder().convert(contents);
                                var tags = appState.sharedPreferencesProvider
                                    .getCards();
                                var tag = CardSave.fromJson(string);
                                tag.id = const Uuid().v4();
                                tags.add(tag);
                                appState.sharedPreferencesProvider
                                    .setCards(tags);
                                appState.changesMade();
                              } catch (_) {
                                var uid4 = contents.sublist(0, 4);
                                var uid7 = contents.sublist(0, 7);
                                var uid4sak = contents[5];
                                var uid4atqa = Uint8List.fromList(
                                    [contents[7], contents[6]]);

                                final uid4Controller = TextEditingController(
                                    text: bytesToHexSpace(uid4));
                                final sak4Controller = TextEditingController(
                                    text: bytesToHex(
                                        Uint8List.fromList([uid4sak])));
                                final atqa4Controller = TextEditingController(
                                    text: bytesToHexSpace(uid4atqa));
                                final uid7Controller = TextEditingController(
                                    text: bytesToHexSpace(uid7));
                                final sak7Controller =
                                    TextEditingController(text: "");
                                final atqa7Controller =
                                    TextEditingController(text: "");
                                final nameController =
                                    TextEditingController(text: "");

                                await showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title:
                                          Text(localizations.correct_tag_data),
                                      content: StatefulBuilder(builder:
                                          (BuildContext context,
                                              StateSetter setState) {
                                        return SingleChildScrollView(
                                            child: Column(children: [
                                          Column(children: [
                                            const SizedBox(height: 20),
                                            Text(localizations.uid_len(4)),
                                            const SizedBox(height: 10),
                                            TextFormField(
                                              controller: uid4Controller,
                                              decoration: InputDecoration(
                                                  labelText: localizations.uid,
                                                  hintText: localizations
                                                      .enter_something("UID")),
                                            ),
                                            const SizedBox(height: 20),
                                            TextFormField(
                                              controller: sak4Controller,
                                              decoration: InputDecoration(
                                                  labelText: localizations.sak,
                                                  hintText: localizations
                                                      .enter_something("SAK")),
                                            ),
                                            const SizedBox(height: 20),
                                            TextFormField(
                                              controller: atqa4Controller,
                                              decoration: InputDecoration(
                                                  labelText: localizations.atqa,
                                                  hintText: localizations
                                                      .enter_something("ATQA")),
                                            ),
                                            const SizedBox(height: 40),
                                          ]),
                                          Column(children: [
                                            Text(localizations.uid_len(7)),
                                            const SizedBox(height: 10),
                                            TextFormField(
                                              controller: uid7Controller,
                                              decoration: InputDecoration(
                                                  labelText: localizations.uid,
                                                  hintText: localizations
                                                      .enter_something("UID")),
                                            ),
                                            const SizedBox(height: 20),
                                            TextFormField(
                                              controller: sak7Controller,
                                              decoration: InputDecoration(
                                                  labelText: localizations.sak,
                                                  hintText: localizations
                                                      .enter_something(
                                                          "SAK (08)")),
                                            ),
                                            const SizedBox(height: 20),
                                            TextFormField(
                                              controller: atqa7Controller,
                                              decoration: InputDecoration(
                                                  labelText: localizations.atqa,
                                                  hintText: localizations
                                                      .enter_something(
                                                          "ATQA (00 44)")),
                                            ),
                                            const SizedBox(height: 40)
                                          ]),
                                          TextFormField(
                                            controller: nameController,
                                            decoration: InputDecoration(
                                                labelText: localizations.name,
                                                hintText:
                                                    localizations.enter_name),
                                          ),
                                          DropdownButton<MifareClassicType>(
                                            value: selectedType,
                                            items: [
                                              MifareClassicType.m1k,
                                              MifareClassicType.m2k,
                                              MifareClassicType.m4k,
                                              MifareClassicType.mini
                                            ].map<
                                                    DropdownMenuItem<
                                                        MifareClassicType>>(
                                                (MifareClassicType type) {
                                              return DropdownMenuItem<
                                                  MifareClassicType>(
                                                value: type,
                                                child: Text(
                                                    "Mifare Classic ${mfClassicGetName(type)}"),
                                              );
                                            }).toList(),
                                            onChanged:
                                                (MifareClassicType? newValue) {
                                              setState(() {
                                                selectedType = newValue!;
                                              });
                                              appState.changesMade();
                                            },
                                          )
                                        ]));
                                      }),
                                      actions: [
                                        ElevatedButton(
                                          onPressed: () async {
                                            List<Uint8List> blocks = [];
                                            for (var i = 0;
                                                i < contents.length;
                                                i += 16) {
                                              if (i + 16 > contents.length) {
                                                break;
                                              }
                                              blocks.add(
                                                  contents.sublist(i, i + 16));
                                            }
                                            var tags = appState
                                                .sharedPreferencesProvider
                                                .getCards();
                                            var tag = CardSave(
                                              id: const Uuid().v4(),
                                              name: nameController.text,
                                              sak: hexToBytes(sak4Controller
                                                  .text
                                                  .replaceAll(" ", ""))[0],
                                              atqa: hexToBytes(atqa4Controller
                                                  .text
                                                  .replaceAll(" ", "")),
                                              uid: uid4Controller.text,
                                              tag: mfClassicGetChameleonTagType(
                                                  selectedType),
                                              data: blocks,
                                            );
                                            tags.add(tag);
                                            appState.sharedPreferencesProvider
                                                .setCards(tags);
                                            appState.changesMade();
                                            Navigator.pop(context);
                                          },
                                          child: Text(localizations
                                              .save_as("4 byte UID")),
                                        ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            List<Uint8List> blocks = [];
                                            for (var i = 0;
                                                i < contents.length;
                                                i += 16) {
                                              blocks.add(
                                                  contents.sublist(i, i + 16));
                                            }
                                            var tags = appState
                                                .sharedPreferencesProvider
                                                .getCards();
                                            var tag = CardSave(
                                              id: const Uuid().v4(),
                                              name: nameController.text,
                                              sak: hexToBytes(sak7Controller
                                                  .text
                                                  .replaceAll(" ", ""))[0],
                                              atqa: hexToBytes(atqa7Controller
                                                  .text
                                                  .replaceAll(" ", "")),
                                              uid: uid7Controller.text,
                                              tag: mfClassicGetChameleonTagType(
                                                  selectedType),
                                              data: blocks,
                                            );
                                            tags.add(tag);
                                            appState.sharedPreferencesProvider
                                                .setCards(tags);
                                            appState.changesMade();
                                            Navigator.pop(context);
                                          },
                                          child: Text(localizations
                                              .save_as("7 byte UID")),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(
                                                context); // Close the modal without saving
                                          },
                                          child: Text(localizations.cancel),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                            }
                          },
                          style: ButtonStyle(
                            shape: MaterialStateProperty.all<
                                RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18.0),
                              ),
                            ),
                          ),
                          child: const Icon(Icons.add),
                        ),
                      );
                    } else {
                      final tag = tags[index - 1];
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: ElevatedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(tag.name),
                                  content: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Text("${localizations.uid}: ${tag.uid}"),
                                      Text(
                                          "${localizations.tag_type}: ${chameleonTagToString(tag.tag)}"),
                                      Text(
                                          "${localizations.sak}: ${tag.sak == 0 ? localizations.unavailable : bytesToHex(u8ToBytes(tag.sak))}"),
                                      Text(
                                          "${localizations.atqa}: ${tag.atqa.asMap().containsKey(0) ? bytesToHex(u8ToBytes(tag.atqa[0])) : ""} ${tag.atqa.asMap().containsKey(1) ? bytesToHex(u8ToBytes(tag.atqa[1])) : localizations.unavailable}"),
                                    ],
                                  ),
                                  actions: [
                                    IconButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return CardEditMenu(tagSave: tag);
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
                                              title: Text(localizations
                                                  .select_save_format),
                                              actions: [
                                                if (isMifareClassic(tag.tag))
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      await saveTag(
                                                          tag, appState, true);
                                                      Navigator.pop(context);
                                                    },
                                                    child: Text(localizations
                                                        .save_as(".bin")),
                                                  ),
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    await saveTag(
                                                        tag, appState, false);
                                                    Navigator.pop(context);
                                                  },
                                                  child: Text(localizations
                                                      .save_as(".json")),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        var tags = appState
                                            .sharedPreferencesProvider
                                            .getCards();
                                        List<CardSave> output = [];
                                        for (var tagTest in tags) {
                                          if (tagTest.id != tag.id) {
                                            output.add(tagTest);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setCards(output);
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
                              },
                            );
                          },
                          style: ButtonStyle(
                            shape: MaterialStateProperty.all<
                                RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18.0),
                              ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Row(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Icon(
                                        (chameleonTagToFrequency(tag.tag) ==
                                                TagFrequency.hf)
                                            ? Icons.credit_card
                                            : Icons.wifi,
                                        color: tag.color,
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Column(
                                          children: [
                                            Text(
                                              tag.name,
                                              style: const TextStyle(
                                                fontSize: 24,
                                              ),
                                            ),
                                            Text(
                                              chameleonTagToString(tag.tag) +
                                                  ((chameleonTagSaveCheckForMifareClassicEV1(
                                                          tag))
                                                      ? " EV1"
                                                      : ""),
                                              style: const TextStyle(
                                                fontSize: 24,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return CardEditMenu(tagSave: tag);
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
                                              title: Text(localizations
                                                  .select_save_format),
                                              actions: [
                                                if (isMifareClassic(tag.tag))
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      await saveTag(
                                                          tag, appState, true);
                                                      Navigator.pop(context);
                                                    },
                                                    child: Text(localizations
                                                        .save_as(".bin")),
                                                  ),
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    await saveTag(
                                                        tag, appState, false);
                                                    Navigator.pop(context);
                                                  },
                                                  child: Text(localizations
                                                      .save_as(".json")),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        var tags = appState
                                            .sharedPreferencesProvider
                                            .getCards();
                                        List<CardSave> output = [];
                                        for (var tagTest in tags) {
                                          if (tagTest.id != tag.id) {
                                            output.add(tagTest);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setCards(output);
                                        appState.changesMade();
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                  staggeredTileBuilder: (int index) => StaggeredTile.fit(
                      index == 0
                          ? 2
                          : 1), // 2 for the "Add" button, 1 for others
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "${localizations.dictionaries}:",
                style: const TextStyle(fontSize: 20),
              ),
            ),
            Expanded(
              child: Card(
                child: StaggeredGridView.countBuilder(
                  padding: const EdgeInsets.all(20),
                  crossAxisCount:
                      MediaQuery.of(context).size.width >= 600 ? 2 : 1,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  itemCount: dictionaries.length + 1,
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: ElevatedButton(
                          onPressed: () async {
                            FilePickerResult? result =
                                await FilePicker.platform.pickFiles();

                            if (result != null) {
                              File file = File(result.files.single.path!);
                              String contents;
                              try {
                                contents = const Utf8Decoder()
                                    .convert(await file.readAsBytes());
                              } catch (e) {
                                return;
                              }

                              List<Uint8List> keys = [];
                              for (var key in contents.split("\n")) {
                                key = key.trim();
                                if (key.length == 12 && isValidHexString(key)) {
                                  keys.add(hexToBytes(key));
                                }
                              }

                              if (keys.isEmpty) {
                                return;
                              }

                              var dictionaries = appState
                                  .sharedPreferencesProvider
                                  .getDictionaries();
                              dictionaries.add(Dictionary(
                                  id: const Uuid().v4(),
                                  name: result.files.single.name.split(".")[0],
                                  keys: keys));
                              appState.sharedPreferencesProvider
                                  .setDictionaries(dictionaries);
                              appState.changesMade();
                            }
                          },
                          style: ButtonStyle(
                            shape: MaterialStateProperty.all<
                                RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18.0),
                              ),
                            ),
                          ),
                          child: const Icon(Icons.add),
                        ),
                      );
                    } else {
                      final dictionary = dictionaries[index - 1];
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: ElevatedButton(
                          onPressed: () {
                            String output = "";
                            for (var key in dictionary.keys) {
                              output += "${bytesToHexSpace(key)}\n";
                            }
                            output.trim();
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(dictionary.name),
                                  content: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Text(
                                          "${localizations.key_count}: ${dictionary.keys.length}"),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        height: 400,
                                        width: 600,
                                        child: ListView(
                                          children: [
                                            Text(
                                              output,
                                              style: const TextStyle(
                                                  fontFamily: 'RobotoMono',
                                                  fontSize: 16.0),
                                            ),
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                  actions: [
                                    IconButton(
                                      onPressed: () async {
                                        await dictMergeDialog(
                                            context, dictionary);
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.merge),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return DictionaryEditMenu(
                                                dict: dictionary);
                                          },
                                        );
                                      },
                                      icon: const Icon(Icons.edit),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        try {
                                          await FileSaver.instance.saveAs(
                                              name: '${dictionary.name}.dic',
                                              bytes: dictionary.toFile(),
                                              ext: 'bin',
                                              mimeType: MimeType.other);
                                        } on UnimplementedError catch (_) {
                                          String? outputFile = await FilePicker
                                              .platform
                                              .saveFile(
                                            dialogTitle:
                                                '${localizations.output_file}:',
                                            fileName: '${dictionary.name}.dic',
                                          );

                                          if (outputFile != null) {
                                            var file = File(outputFile);
                                            await file.writeAsBytes(
                                                dictionary.toFile());
                                          }
                                        }
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        var dictionaries = appState
                                            .sharedPreferencesProvider
                                            .getDictionaries();
                                        List<Dictionary> output = [];
                                        for (var dict in dictionaries) {
                                          if (dict.id != dictionary.id) {
                                            output.add(dict);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setDictionaries(output);
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
                              },
                            );
                          },
                          style: ButtonStyle(
                            shape: MaterialStateProperty.all<
                                RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18.0),
                              ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Row(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.key_rounded,
                                        color: dictionary.color,
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Column(
                                          children: [
                                            Text(
                                              dictionary.name,
                                              style: const TextStyle(
                                                fontSize: 24,
                                              ),
                                            ),
                                            Text(
                                              "${localizations.key_count}: ${dictionary.keys.length}",
                                              style: const TextStyle(
                                                fontSize: 24,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return DictionaryEditMenu(
                                                dict: dictionary);
                                          },
                                        );
                                      },
                                      icon: const Icon(Icons.edit),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        try {
                                          await FileSaver.instance.saveAs(
                                              name: dictionary.name,
                                              bytes: dictionary.toFile(),
                                              ext: 'dic',
                                              mimeType: MimeType.other);
                                        } on UnimplementedError catch (_) {
                                          String? outputFile = await FilePicker
                                              .platform
                                              .saveFile(
                                            dialogTitle:
                                                '${localizations.output_file}:',
                                            fileName: '${dictionary.name}.dic',
                                          );

                                          if (outputFile != null) {
                                            var file = File(outputFile);
                                            await file.writeAsBytes(
                                                dictionary.toFile());
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        var dictionaries = appState
                                            .sharedPreferencesProvider
                                            .getDictionaries();
                                        List<Dictionary> output = [];
                                        for (var dict in dictionaries) {
                                          if (dict.id != dictionary.id) {
                                            output.add(dict);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setDictionaries(output);
                                        appState.changesMade();
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                  staggeredTileBuilder: (int index) => StaggeredTile.fit(
                      index == 0
                          ? 2
                          : 1), // 2 for the "Add" button, 1 for others
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> dictMergeDialog(BuildContext context, Dictionary mergeDict) {
    var appState = context.read<ChameleonGUIState>();
    var dicts = appState.sharedPreferencesProvider.getDictionaries();

    dicts.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: DictMergeDelegate(dicts, mergeDict),
    );
  }
}

class DictMergeDelegate extends SearchDelegate<String> {
  final List<Dictionary> dicts;
  final Dictionary mergeDict;
  List<bool> selectedDicts = [];

  DictMergeDelegate(this.dicts, this.mergeDict) {
    selectedDicts = List.filled(dicts.length, false);
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
      const SizedBox(width: 10),
      IconButton(
        icon: const Icon(Icons.merge),
        onPressed: () {
          List<Dictionary> selectedForMerge = [];
          List<Dictionary> output = dicts;

          // Get selected dicts
          for (var i = 0; i < selectedDicts.length; i++) {
            if (selectedDicts[i]) {
              selectedForMerge.add(dicts[i]);
            }
          }

          // Merge
          for (var dict in selectedForMerge) {
            mergeDict.keys = mergeDict.keys + dict.keys;
          }

          // Deduplicate
          mergeDict.keys = <int, Uint8List>{
            for (var key in mergeDict.keys) Object.hashAll(key): key
          }.values.toList();

          // Replace
          for (var i = 0; i < output.length; i++) {
            if (output[i].id == mergeDict.id) {
              output[i] = mergeDict;
            }
          }

          appState.sharedPreferencesProvider.setDictionaries(output);

          Navigator.pop(context);
          appState.changesMade();
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
        if (dict.id == mergeDict.id) {
          return Container();
        }
        return CheckboxListTile(
          value: selectedDicts[index],
          title: Text(dict.name),
          secondary: Icon(Icons.key, color: dict.color),
          subtitle: Text("${dict.keys.length.toString()} keys"),
          onChanged: (value) {},
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        var appState = context.read<ChameleonGUIState>();
        if (dict.id == mergeDict.id) {
          return Container();
        }
        return CheckboxListTile(
          value: selectedDicts[index],
          title: Text(dict.name),
          secondary: Icon(Icons.key, color: dict.color),
          subtitle: Text("${dict.keys.length.toString()} keys"),
          onChanged: (value) {
            selectedDicts[index] = value!;
            appState.changesMade();
          },
        );
      },
    );
  }
}
