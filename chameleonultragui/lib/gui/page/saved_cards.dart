import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:chameleonultragui/gui/component/saved_card.dart';
import 'package:chameleonultragui/gui/menu/dictionary_edit.dart';
import 'package:chameleonultragui/gui/menu/card_view.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/gui/menu/card_edit.dart';
import 'package:chameleonultragui/gui/menu/dictionary_view.dart';
import 'package:uuid/uuid.dart';
import 'package:chameleonultragui/gui/menu/confirm_delete.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class SavedCardsPage extends StatefulWidget {
  const SavedCardsPage({super.key});

  @override
  SavedCardsPageState createState() => SavedCardsPageState();
}

class SavedCardsPageState extends State<SavedCardsPage> {
  TagType selectedType = TagType.unknown;

  CardSave pm3JsonToCardSave(String json) {
    Map<String, dynamic> data = jsonDecode(json);

    final String id = const Uuid().v4();
    final String uid = data['Card']['UID'] as String;
    String sakString = data['Card']['SAK'] as String;
    final int sak = hexToBytes(sakString)[0];
    String atqaString = data['Card']['ATQA'] as String;
    final List<int> atqa = [
      int.parse(atqaString.substring(2), radix: 16),
      int.parse(atqaString.substring(0, 2), radix: 16)
    ];
    final List<int> ats = [];
    final String name = uid;
    const Color color = Colors.deepOrange;
    final TagType tag;
    List<Uint8List> tagData = [];

    List<String> blocks = [];
    Map<String, dynamic> blockData = data['blocks'] as Map<String, dynamic>;
    for (int i = 0; blockData.containsKey(i.toString()); i++) {
      blocks.add(blockData[i.toString()] as String);
    }

    //Check if a block has more than 16 Bytes, Ultralight, return as unknown
    if (blocks[0].length > 32) {
      tag = TagType.unknown;
    } else {
      tag = mfClassicGetChameleonTagType(
          mfClassicGetCardTypeByBlockCount(blocks.length));
    }

    for (var block in blocks) {
      tagData.add(hexToBytes(block));
    }

    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
        ats: Uint8List.fromList(ats),
        atqa: Uint8List.fromList(atqa));
  }

  CardSave flipperNfcToCardSave(String data) {
    final String id = const Uuid().v4();
    final String uid =
        RegExp(r'UID:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
    final int sak = hexToBytes(
        RegExp(r'SAK:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!)[0];
    String atqaString =
        RegExp(r'ATQA:\s+([\dA-Fa-f ]+)').firstMatch(data)!.group(1)!;
    final List<int> atqa = [
      int.parse(atqaString.substring(0, 2), radix: 16),
      int.parse(atqaString.substring(2), radix: 16)
    ];
    final List<int> ats = [];
    final String name = uid;
    const Color color = Colors.deepOrange;
    final TagType tag;
    List<Uint8List> tagData = [];
    List<String> blocks = [];
    for (var block in data.split("\n")) {
      if (block.startsWith("Block")) {
        blocks.add(block.split(":")[1].trim().replaceAll('?', '0'));
      }
    }

    //Check if a block has more than 16 Bytes, Ultralight, return as unknown
    if (blocks[0].replaceAll(' ', '').length > 32) {
      tag = TagType.unknown;
    } else {
      tag = mfClassicGetChameleonTagType(
          mfClassicGetCardTypeByBlockCount(blocks.length));
    }

    for (var block in blocks) {
      tagData.add(hexToBytes(block));
    }

    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
        ats: Uint8List.fromList(ats),
        atqa: Uint8List.fromList(atqa));
  }

  CardSave mctToCardSave(String data) {
    final String id = const Uuid().v4();
    final String uid = data.split("\n")[1].substring(0, 8);
    final int sak = hexToBytes(data.split("\n")[1].substring(10, 12))[0];
    String atqaString = data.split("\n")[1].substring(12, 16);
    final List<int> atqa = [
      int.parse(atqaString.substring(2), radix: 16),
      int.parse(atqaString.substring(0, 2), radix: 16)
    ];
    final List<int> ats = [];
    final String name = uid;
    const Color color = Colors.deepOrange;
    final TagType tag;
    List<Uint8List> tagData = [];
    List<String> blocks = [];
    for (var block in data.split("\n")) {
      if (!block.startsWith("+Sector")) {
        blocks.add(block.trim());
      }
    }

    //Check if a block has more than 16 Bytes, Ultralight, return as unknown
    if (blocks[0].replaceAll(' ', '').length > 32) {
      tag = TagType.unknown;
    } else {
      tag = mfClassicGetChameleonTagType(
          mfClassicGetCardTypeByBlockCount(blocks.length));
    }

    for (var block in blocks) {
      tagData.add(hexToBytes(block));
    }

    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
        ats: Uint8List.fromList(ats),
        atqa: Uint8List.fromList(atqa));
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var dictionaries = appState.sharedPreferencesProvider.getDictionaries();
    var tags = appState.sharedPreferencesProvider.getCards();
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.saved_cards),
      ),
      body: Column(
        children: [
          Expanded(
            child: Card(
                child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  localizations.cards,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: ElevatedButton(
                    onPressed: () async {
                      FilePickerResult? result =
                          await FilePicker.platform.pickFiles();

                      if (result != null) {
                        File file = File(result.files.single.path!);
                        var contents = await file.readAsBytes();
                        try {
                          var string = const Utf8Decoder().convert(contents);
                          var tags =
                              appState.sharedPreferencesProvider.getCards();
                          CardSave tag;
                          if (string.contains("\"Created\": \"proxmark3\",")) {
                            // PM3 JSON
                            tag = pm3JsonToCardSave(string);
                          } else if (string
                              .contains("Filetype: Flipper NFC device")) {
                            // Flipper NFC
                            tag = flipperNfcToCardSave(string);
                          } else if (string.contains("+Sector: 0")) {
                            // Mifare Classic Tool
                            tag = mctToCardSave(string);
                          } else {
                            tag = CardSave.fromJson(string);
                          }

                          tags.add(tag);
                          appState.sharedPreferencesProvider.setCards(tags);
                          appState.changesMade();
                        } catch (_) {
                          selectedType = getTagTypeByDumpSize(contents.length);

                          if (selectedType == TagType.unknown) {
                            return;
                          }

                          bool hasUid4Support = false;
                          Uint8List uid4 = Uint8List(0);
                          Uint8List uid7 = Uint8List(0);
                          int uid4Sak = 0;
                          Uint8List uid4Atqa = Uint8List(0);
                          int uid7Sak = 0;
                          Uint8List uid7Atqa = Uint8List(0);

                          if (isMifareClassic(selectedType)) {
                            hasUid4Support = true;
                            uid4 = contents.sublist(0, 4);
                            uid7 = contents.sublist(0, 7);
                            uid4Sak = contents[5];
                            uid4Atqa =
                                Uint8List.fromList([contents[7], contents[6]]);
                          } else if (isMifareUltralight(selectedType)) {
                            uid7Atqa = Uint8List.fromList([0x00, 0x44]);
                            uid7 = Uint8List.fromList([
                              ...contents.sublist(0, 3),
                              ...contents.sublist(4, 8)
                            ]);
                          }

                          final uid4Controller = TextEditingController(
                              text: bytesToHexSpace(uid4));
                          final sak4Controller = TextEditingController(
                              text: bytesToHex(Uint8List.fromList([uid4Sak])));
                          final atqa4Controller = TextEditingController(
                              text: bytesToHexSpace(uid4Atqa));
                          final uid7Controller = TextEditingController(
                              text: bytesToHexSpace(uid7));
                          final sak7Controller = TextEditingController(
                              text: bytesToHex(Uint8List.fromList([uid7Sak])));
                          final atqa7Controller = TextEditingController(
                              text: bytesToHexSpace(uid7Atqa));
                          final nameController =
                              TextEditingController(text: "");

                          if (!context.mounted) {
                            return;
                          }

                          await showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text(localizations.correct_tag_data),
                                content: StatefulBuilder(builder:
                                    (BuildContext context,
                                        StateSetter setState) {
                                  return SingleChildScrollView(
                                      child: Column(children: [
                                    if (hasUid4Support)
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
                                                .enter_something("SAK (08)")),
                                      ),
                                      const SizedBox(height: 20),
                                      TextFormField(
                                        controller: atqa7Controller,
                                        decoration: InputDecoration(
                                            labelText: localizations.atqa,
                                            hintText:
                                                localizations.enter_something(
                                                    "ATQA (00 44)")),
                                      ),
                                      const SizedBox(height: 40)
                                    ]),
                                    TextFormField(
                                      controller: nameController,
                                      decoration: InputDecoration(
                                          labelText: localizations.name,
                                          hintText:
                                              localizations.enter_name_of_card),
                                    ),
                                    DropdownButton<TagType>(
                                      value: selectedType,
                                      items: getTagTypesByFrequency(
                                              TagFrequency.hf)
                                          .map<DropdownMenuItem<TagType>>(
                                              (TagType type) {
                                        return DropdownMenuItem<TagType>(
                                          value: type,
                                          child:
                                              Text(chameleonTagToString(type)),
                                        );
                                      }).toList(),
                                      onChanged: (TagType? newValue) {
                                        setState(() {
                                          selectedType = newValue!;
                                        });
                                        appState.changesMade();
                                      },
                                    )
                                  ]));
                                }),
                                actions: [
                                  if (hasUid4Support)
                                    ElevatedButton(
                                      onPressed: () async {
                                        List<Uint8List> blocks = [];
                                        int blockSize =
                                            isMifareClassic(selectedType)
                                                ? 16
                                                : 4;

                                        for (var i = 0;
                                            i < contents.length;
                                            i += blockSize) {
                                          if (i + blockSize > contents.length) {
                                            break;
                                          }
                                          blocks.add(contents.sublist(
                                              i, i + blockSize));
                                        }

                                        var tags = appState
                                            .sharedPreferencesProvider
                                            .getCards();

                                        if (sak4Controller.text.length != 2 ||
                                            atqa4Controller.text.length != 5) {
                                          return showDialog(
                                            context: context,
                                            barrierDismissible: true,
                                            builder: (_) => AlertDialog(
                                                title:
                                                    Text(localizations.error),
                                                actions: [
                                                  ElevatedButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                    },
                                                    child:
                                                        Text(localizations.ok),
                                                  ),
                                                ],
                                                content: Text(localizations
                                                    .invalid_input)),
                                          );
                                        }

                                        var tag = CardSave(
                                            name: nameController.text,
                                            sak: hexToBytes(
                                                sak4Controller.text)[0],
                                            atqa: hexToBytes(
                                                atqa4Controller.text),
                                            uid: uid4Controller.text,
                                            tag: selectedType,
                                            data: blocks);
                                        tags.add(tag);
                                        appState.sharedPreferencesProvider
                                            .setCards(tags);
                                        appState.changesMade();
                                        Navigator.pop(context);
                                      },
                                      child: Text(localizations.save_as(
                                          localizations.x_byte_uid(4))),
                                    ),
                                  ElevatedButton(
                                    onPressed: () async {
                                      List<Uint8List> blocks = [];
                                      int blockSize =
                                          isMifareClassic(selectedType)
                                              ? 16
                                              : 4;

                                      for (var i = 0;
                                          i < contents.length;
                                          i += blockSize) {
                                        blocks.add(
                                            contents.sublist(i, i + blockSize));
                                      }

                                      var tags = appState
                                          .sharedPreferencesProvider
                                          .getCards();

                                      if (sak7Controller.text.length != 2 ||
                                          atqa7Controller.text.length != 5) {
                                        return showDialog(
                                          context: context,
                                          barrierDismissible: true,
                                          builder: (_) => AlertDialog(
                                              title: Text(localizations.error),
                                              actions: [
                                                ElevatedButton(
                                                  onPressed: () {
                                                    Navigator.pop(context);
                                                  },
                                                  child: Text(localizations.ok),
                                                ),
                                              ],
                                              content: Text(
                                                  localizations.invalid_input)),
                                        );
                                      }

                                      var tag = CardSave(
                                          name: nameController.text,
                                          sak: hexToBytes(
                                              sak7Controller.text)[0],
                                          atqa:
                                              hexToBytes(atqa7Controller.text),
                                          uid: uid7Controller.text,
                                          tag: selectedType,
                                          data: blocks);
                                      tags.add(tag);
                                      appState.sharedPreferencesProvider
                                          .setCards(tags);
                                      appState.changesMade();
                                      Navigator.pop(context);
                                    },
                                    child: Text(localizations
                                        .save_as(localizations.x_byte_uid(7))),
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
                    style: customCardButtonStyle(appState),
                    child: const Icon(Icons.add),
                  ),
                )
              ]),
              Expanded(
                  child: SingleChildScrollView(
                      child: AlignedGridView.count(
                          clipBehavior: Clip.antiAlias,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(10),
                          crossAxisCount:
                              MediaQuery.of(context).size.width >= 700 ? 2 : 1,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          itemCount: tags.length,
                          shrinkWrap: true,
                          itemBuilder: (BuildContext context, int index) {
                            final tag = tags[index];
                            return SavedCard(
                              icon: (chameleonTagToFrequency(tag.tag) ==
                                      TagFrequency.hf)
                                  ? Icons.credit_card
                                  : Icons.wifi,
                              iconColor: tag.color,
                              firstLine: tag.name.isEmpty ? "⠀" : tag.name,
                              secondLine: chameleonCardToString(tag),
                              itemIndex: index,
                              onPressed: () {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return CardViewMenu(tagSave: tag);
                                    });
                              },
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
                                          title: Text(
                                              localizations.select_save_format),
                                          actions: [
                                            ElevatedButton(
                                              onPressed: () async {
                                                await saveTag(
                                                    tag, context, true);
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                              child: Text(localizations
                                                  .save_as(".bin")),
                                            ),
                                            ElevatedButton(
                                              onPressed: () async {
                                                await saveTag(
                                                    tag, context, false);
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                              child: Text(localizations
                                                  .save_as(".json")),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  icon: const Icon(Icons.download),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    if (appState.sharedPreferencesProvider
                                            .getConfirmDelete() ==
                                        true) {
                                      var confirm = await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return ConfirmDeletionMenu(
                                              thingBeingDeleted: tag.name);
                                        },
                                      );

                                      if (confirm != true) {
                                        return;
                                      }
                                    }
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
                            );
                          }))),
            ])),
          ),
          Expanded(
            child: Card(
                child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  localizations.dictionaries,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(10),
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

                        var dictionaries = appState.sharedPreferencesProvider
                            .getDictionaries();
                        dictionaries.add(Dictionary(
                            name: result.files.single.name.split(".")[0],
                            keys: keys));
                        appState.sharedPreferencesProvider
                            .setDictionaries(dictionaries);
                        appState.changesMade();
                      }
                    },
                    style: customCardButtonStyle(appState),
                    child: const Icon(Icons.add),
                  ),
                )
              ]),
              Expanded(
                  child: SingleChildScrollView(
                      child: AlignedGridView.count(
                          clipBehavior: Clip.antiAlias,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(10),
                          crossAxisCount:
                              MediaQuery.of(context).size.width >= 700 ? 2 : 1,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          itemCount: dictionaries.length,
                          shrinkWrap: true,
                          itemBuilder: (BuildContext context, int index) {
                            final dictionary = dictionaries[index];
                            return SavedCard(
                              icon: Icons.key,
                              iconColor: dictionary.color,
                              firstLine: dictionary.name,
                              secondLine:
                                  "${localizations.key_count}: ${dictionary.keys.length}",
                              itemIndex: index,
                              onPressed: () {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return DictionaryViewMenu(
                                          dictionary: dictionary);
                                    });
                              },
                              children: [
                                IconButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return DictionaryEditMenu(
                                            dictionary: dictionary);
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
                                      String? outputFile =
                                          await FilePicker.platform.saveFile(
                                        dialogTitle:
                                            '${localizations.output_file}:',
                                        fileName: '${dictionary.name}.dic',
                                      );

                                      if (outputFile != null) {
                                        var file = File(outputFile);
                                        await file
                                            .writeAsBytes(dictionary.toFile());
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.download),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    if (appState.sharedPreferencesProvider
                                            .getConfirmDelete() ==
                                        true) {
                                      var confirm = await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return ConfirmDeletionMenu(
                                              thingBeingDeleted:
                                                  dictionary.name);
                                        },
                                      );

                                      if (confirm != true) {
                                        return;
                                      }
                                    }
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
                            );
                          }))),
            ])),
          ),
        ],
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
    var localizations = AppLocalizations.of(context)!;

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
          subtitle: Text(
              "${dict.keys.length.toString()} ${localizations.total_keys.toLowerCase()}"),
          onChanged: (value) {},
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));
    var localizations = AppLocalizations.of(context)!;

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
          subtitle: Text(
              "${dict.keys.length.toString()} ${localizations.total_keys.toLowerCase()}"),
          onChanged: (value) {
            selectedDicts[index] = value!;
            appState.changesMade();
          },
        );
      },
    );
  }
}
