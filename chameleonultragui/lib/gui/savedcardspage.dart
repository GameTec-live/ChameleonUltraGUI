import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/files.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:uuid/uuid.dart';

class SavedCardsPage extends StatefulWidget {
  const SavedCardsPage({super.key});

  @override
  SavedCardsPageState createState() => SavedCardsPageState();
}

class SavedCardsPageState extends State<SavedCardsPage> {
  MifareClassicType selectedType = MifareClassicType.m1k;

  Future<void> saveTag(
      ChameleonTagSave tag, MyAppState appState, bool bin) async {

    final fileName = tag.name;
    final fileExtension = bin ? 'bin' : 'json';

    Uint8List bytes = Uint8List(0);
    if (bin) {
      List<int> tagDump = [];
      for (var block in tag.data) {
        tagDump.addAll(block);
      }

      bytes = Uint8List.fromList(tagDump);
    } else {
      bytes = const Utf8Encoder().convert(tag.toJson());
    }

    await saveFile(appState: appState, fileName: fileName, fileExtension: fileExtension, bytes: bytes);
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var dictionaries =
        appState.sharedPreferencesProvider.getChameleonDictionaries();
    var tags = appState.sharedPreferencesProvider.getChameleonTags();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Cards'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "Cards:",
                style: TextStyle(fontSize: 20),
              ),
            ),
            Expanded(
              child: Card(
                child: StaggeredGridView.countBuilder(
                  padding: const EdgeInsets.all(20),
                  crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 2 : 1,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  itemCount: tags.length + 1,
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: ElevatedButton(
                          onPressed: () async {
                            FileResult? file = await pickFile(appState);
                            if (file == null) {
                              return;
                            }

                            String tagName = file.name;
                            Uint8List contents = file.bytes;

                            try {
                              var string = file.asText();
                              var tags = appState.sharedPreferencesProvider
                                  .getChameleonTags();
                              var tag = ChameleonTagSave.fromJson(string);
                              tag.id = const Uuid().v4();
                              tags.add(tag);

                              appState.sharedPreferencesProvider
                                  .setChameleonTags(tags);
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
                                  TextEditingController(text: bytesToHex(
                                      Uint8List.fromList([uid4sak])));
                              final atqa7Controller =
                                  TextEditingController(text: bytesToHexSpace(uid4atqa));
                              final nameController =
                                  TextEditingController(text: tagName);

                              // ignore: use_build_context_synchronously
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text('Correct tag details'),
                                    content: StatefulBuilder(builder:
                                        (BuildContext context,
                                            StateSetter setState) {
                                      return SingleChildScrollView(
                                          child: Column(children: [
                                        Column(children: [
                                          const SizedBox(height: 20),
                                          const Text('UID 4 byte length'),
                                          const SizedBox(height: 10),
                                          TextFormField(
                                            controller: uid4Controller,
                                            decoration: const InputDecoration(
                                                labelText: 'UID',
                                                hintText: 'Enter UID'),
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            controller: sak4Controller,
                                            decoration: const InputDecoration(
                                                labelText: 'SAK',
                                                hintText: 'Enter SAK'),
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            controller: atqa4Controller,
                                            decoration: const InputDecoration(
                                                labelText: 'ATQA',
                                                hintText: 'Enter ATQA'),
                                          ),
                                          const SizedBox(height: 40),
                                        ]),
                                        Column(children: [
                                          const Text('UID 7 byte length'),
                                          const SizedBox(height: 10),
                                          TextFormField(
                                            controller: uid7Controller,
                                            decoration: const InputDecoration(
                                                labelText: 'UID',
                                                hintText: 'Enter UID'),
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            controller: sak7Controller,
                                            decoration: const InputDecoration(
                                                labelText: 'SAK',
                                                hintText: 'Enter SAK (08)'),
                                          ),
                                          const SizedBox(height: 20),
                                          TextFormField(
                                            controller: atqa7Controller,
                                            decoration: const InputDecoration(
                                                labelText: 'ATQA',
                                                hintText:
                                                    'Enter ATQA (00 44)'),
                                          ),
                                          const SizedBox(height: 40)
                                        ]),
                                        TextFormField(
                                          controller: nameController,
                                          decoration: const InputDecoration(
                                              labelText: 'Name',
                                              hintText: 'Enter name of card'),
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
                                              .getChameleonTags();
                                          var tag = ChameleonTagSave(
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
                                              .setChameleonTags(tags);
                                          appState.changesMade();
                                          Navigator.pop(context);
                                        },
                                        child:
                                            const Text('Save as 4 byte UID'),
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
                                              .getChameleonTags();
                                          var tag = ChameleonTagSave(
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
                                              .setChameleonTags(tags);
                                          appState.changesMade();
                                          Navigator.pop(context); // Close the modal after saving
                                        },
                                        child:
                                            const Text('Save as 7 byte UID'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(
                                              context); // Close the modal without saving
                                        },
                                        child: const Text('Cancel'),
                                      ),
                                    ],
                                  );
                                },
                              );
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
                                      Text("UID: ${tag.uid}"),
                                      Text("Tag Type: ${tag.tag.name}"),
                                      Text("SAK: ${tag.sak}"),
                                      Text("ATQA: ${tag.atqa[0]} ${tag.atqa[1]}"),
                                    ],
                                  ),
                                  actions: [
                                    const IconButton(
                                      onPressed: null,
                                      icon: Icon(Icons.edit),
                                      tooltip: 'Not implemented yet',
                                    ),

                                    IconButton(
                                      onPressed: () async {
                                        await showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: const Text(
                                                  'Select save format'),
                                              actions: [
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    await saveTag(
                                                        tag, appState, true);
                                                    Navigator.pop(context);
                                                  },
                                                  child: const Text(
                                                      'Save as .bin'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    await saveTag(
                                                        tag, appState, false);
                                                    Navigator.pop(context);
                                                  },
                                                  child: const Text(
                                                      'Save as .json'),
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
                                            .getChameleonTags();
                                        List<ChameleonTagSave> output = [];
                                        for (var tagTest in tags) {
                                          if (tagTest.id != tag.id) {
                                            output.add(tagTest);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setChameleonTags(output);
                                        appState.changesMade();
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),

                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                      child: const Text('Ok'),
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
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.nfc_sharp,
                                        color: Colors.blue,
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
                                              tag.tag.name,
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
                                    const IconButton(
                                      onPressed: null,
                                      icon: Icon(Icons.edit),
                                      tooltip: 'Not implemented yet',
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        await showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: const Text(
                                                  'Select save format'),
                                              actions: [
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    await saveTag(
                                                        tag, appState, true);
                                                    Navigator.pop(context);
                                                  },
                                                  child: const Text(
                                                      'Save as .bin'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    await saveTag(
                                                        tag, appState, false);
                                                    Navigator.pop(context);
                                                  },
                                                  child: const Text(
                                                      'Save as .json'),
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
                                            .getChameleonTags();
                                        List<ChameleonTagSave> output = [];
                                        for (var tagTest in tags) {
                                          if (tagTest.id != tag.id) {
                                            output.add(tagTest);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setChameleonTags(output);
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
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                "Dictionaries:",
                style: TextStyle(fontSize: 20),
              ),
            ),
            Expanded(
              child: Card(
                child: StaggeredGridView.countBuilder(
                  padding: const EdgeInsets.all(20),
                  crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 2 : 1,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  itemCount: dictionaries.length + 1,
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: ElevatedButton(
                          onPressed: () async {
                            FileResult? file = await pickFile(appState);
                            if (file == null) {
                              return;
                            }

                            String contents = file.asText();

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
                                .getChameleonDictionaries();
                            dictionaries.add(ChameleonDictionary(
                                id: const Uuid().v4(),
                                name: file.name,
                                keys: keys));
                            appState.sharedPreferencesProvider
                                .setChameleonDictionaries(dictionaries);
                            appState.changesMade();
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
                            List<String> displayList = [];
                            for (var key in dictionary.keys) {
                              displayList.add(bytesToHex(key).toUpperCase());
                            }

                            final Text keyList = Text(
                              displayList.join('\n'),
                              style: const TextStyle(fontFamily: 'RobotoMono'),
                            );

                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(dictionary.name),
                                  content: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Text("Key Count: ${dictionary.keys.length}"),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        height: 400,
                                        width: 600,
                                        child: ListView(
                                          children: [keyList],
                                        ),
                                      )
                                    ],
                                  ),
                                  actions: [
                                    const IconButton(
                                      onPressed: null,
                                      icon: Icon(Icons.edit),
                                      tooltip: 'Not implemented yet',
                                    ),

                                    IconButton(
                                      onPressed: () async {
                                        await saveFile(
                                          appState: appState,
                                          fileName: '${dictionary.name}.dic',
                                          fileExtension: 'dic',
                                          bytes: dictionary.toFile(),
                                        );
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                    ),

                                    IconButton(
                                      onPressed: () async {
                                        var dictionaries = appState
                                            .sharedPreferencesProvider
                                            .getChameleonDictionaries();
                                        List<ChameleonDictionary> output = [];
                                        for (var dict in dictionaries) {
                                          if (dict.id != dictionary.id) {
                                            output.add(dict);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setChameleonDictionaries(output);
                                        appState.changesMade();
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),

                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                      child: const Text('Ok'),
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
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.key_rounded,
                                        color: Colors.blue,
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
                                              "Key count: ${dictionary.keys.length}",
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
                                    const IconButton(
                                      onPressed: null,
                                      icon: Icon(Icons.edit),
                                      tooltip: 'Not implemented yet',
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        await saveFile(
                                          appState: appState,
                                          fileName: dictionary.name,
                                          fileExtension: 'dic',
                                          bytes: dictionary.toFile(),
                                        );
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        var dictionaries = appState
                                            .sharedPreferencesProvider
                                            .getChameleonDictionaries();
                                        List<ChameleonDictionary> output = [];
                                        for (var dict in dictionaries) {
                                          if (dict.id != dictionary.id) {
                                            output.add(dict);
                                          }
                                        }
                                        appState.sharedPreferencesProvider
                                            .setChameleonDictionaries(output);
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
}
