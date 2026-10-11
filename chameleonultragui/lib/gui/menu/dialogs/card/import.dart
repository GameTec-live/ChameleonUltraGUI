import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' show basename;
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Lets the user pick a card file (JSON, PM3, Flipper, MCT or raw dump) and
/// adds it to the saved cards, asking for the missing details of raw dumps.
///
/// [onFolderSource] is called with the file contents if the file is a folder
/// export instead of a single card.
Future<void> importCardFromFile(
  BuildContext context, {
  String? folderId,
  Future<void> Function(String source)? onFolderSource,
}) async {
  final appState = context.read<ChameleonGUIState>();
  final localizations = AppLocalizations.of(context)!;
  TagType selectedType = TagType.unknown;

  PlatformFile? result = await FilePicker.pickFile();

  if (result != null) {
    File file = File(result.path!);
    var contents = await file.readAsBytes();
    try {
      var string = const Utf8Decoder().convert(contents);
      dynamic decodedJson;
      try {
        decodedJson = jsonDecode(string);
      } catch (_) {
        // Non-JSON formats are handled below.
      }
      if (decodedJson is Map &&
          decodedJson['format'] == 'chameleon-ultra-gui-folder') {
        await onFolderSource?.call(string);
        return;
      }
      var tags = appState.sharedPreferencesProvider.getCards();
      CardSave tag;
      if (string.contains("\"Created\": \"proxmark3\",")) {
        // PM3 JSON
        tag = pm3JsonToCardSave(string);
      } else if (string.contains("Filetype: Flipper NFC device")) {
        // Flipper NFC
        tag = flipperNfcToCardSave(string);
      } else if (string.contains("+Sector: 0")) {
        // Mifare Classic Tool
        tag = mctToCardSave(string);
      } else if (string.contains("Filetype: Flipper RFID key")) {
        // Flipper RFID
        tag = flipperRfidToCardSave(string);
      } else {
        tag = CardSave.fromJson(string);
      }

      tag.name = basename(file.path).contains('.')
          ? basename(file.path).split('.')[0]
          : basename(file.path);
      tag.folderId = folderId;
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
        uid4Atqa = Uint8List.fromList([contents[7], contents[6]]);
      } else if (isMifareUltralight(selectedType)) {
        uid7Atqa = Uint8List.fromList([0x00, 0x44]);
        uid7 = Uint8List.fromList([
          ...contents.sublist(0, 3),
          ...contents.sublist(4, 8),
        ]);
      }

      final uid4Controller = TextEditingController(text: bytesToHexSpace(uid4));
      final sak4Controller = TextEditingController(
        text: bytesToHex(Uint8List.fromList([uid4Sak])),
      );
      final atqa4Controller = TextEditingController(
        text: bytesToHexSpace(uid4Atqa),
      );
      final uid7Controller = TextEditingController(text: bytesToHexSpace(uid7));
      final sak7Controller = TextEditingController(
        text: bytesToHex(Uint8List.fromList([uid7Sak])),
      );
      final atqa7Controller = TextEditingController(
        text: bytesToHexSpace(uid7Atqa),
      );
      final nameController = TextEditingController(text: "");

      if (!context.mounted) {
        return;
      }

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(localizations.correct_tag_data),
            content: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      if (hasUid4Support)
                        Column(
                          children: [
                            const SizedBox(height: 20),
                            Text(localizations.uid_len(4)),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: uid4Controller,
                              inputFormatters: hexFormatter,
                              validator: (value) => validateHex(
                                value,
                                localizations,
                                exactBytes: 4,
                                fieldName: localizations.uid,
                              ),
                              decoration: InputDecoration(
                                labelText: localizations.uid,
                                hintText: localizations.enter_something("UID"),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: sak4Controller,
                              inputFormatters: hexFormatter,
                              validator: (value) => validateHex(
                                value,
                                localizations,
                                exactBytes: 1,
                                fieldName: localizations.sak,
                              ),
                              decoration: InputDecoration(
                                labelText: localizations.sak,
                                hintText: localizations.enter_something("SAK"),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: atqa4Controller,
                              inputFormatters: hexFormatter,
                              validator: (value) => validateHex(
                                value,
                                localizations,
                                exactBytes: 2,
                                fieldName: localizations.atqa,
                              ),
                              decoration: InputDecoration(
                                labelText: localizations.atqa,
                                hintText: localizations.enter_something("ATQA"),
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      Column(
                        children: [
                          Text(localizations.uid_len(7)),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: uid7Controller,
                            inputFormatters: hexFormatter,
                            validator: (value) => validateHex(
                              value,
                              localizations,
                              exactBytes: 7,
                              fieldName: localizations.uid,
                            ),
                            decoration: InputDecoration(
                              labelText: localizations.uid,
                              hintText: localizations.enter_something("UID"),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: sak7Controller,
                            inputFormatters: hexFormatter,
                            validator: (value) => validateHex(
                              value,
                              localizations,
                              exactBytes: 1,
                              fieldName: localizations.sak,
                            ),
                            decoration: InputDecoration(
                              labelText: localizations.sak,
                              hintText: localizations.enter_something("SAK"),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: atqa7Controller,
                            inputFormatters: hexFormatter,
                            validator: (value) => validateHex(
                              value,
                              localizations,
                              exactBytes: 2,
                              fieldName: localizations.atqa,
                            ),
                            decoration: InputDecoration(
                              labelText: localizations.atqa,
                              hintText: localizations.enter_something("ATQA"),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                      TextFormField(
                        controller: nameController,
                        validator: (value) =>
                            validateName(value, localizations),
                        decoration: InputDecoration(
                          labelText: localizations.name,
                          hintText: localizations.enter_name_of_card,
                        ),
                      ),
                      DropdownButton<TagType>(
                        value: selectedType,
                        items: getTagTypesByFrequency(TagFrequency.hf)
                            .map<DropdownMenuItem<TagType>>((TagType type) {
                              return DropdownMenuItem<TagType>(
                                value: type,
                                child: Text(
                                  chameleonTagToString(type, localizations),
                                ),
                              );
                            })
                            .toList(),
                        onChanged: (TagType? newValue) {
                          setState(() {
                            selectedType = newValue!;
                          });
                          appState.changesMade();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              if (hasUid4Support)
                ElevatedButton(
                  onPressed: () async {
                    List<Uint8List> blocks = [];
                    int blockSize = isMifareClassic(selectedType) ? 16 : 4;

                    for (var i = 0; i < contents.length; i += blockSize) {
                      if (i + blockSize > contents.length) {
                        break;
                      }
                      blocks.add(contents.sublist(i, i + blockSize));
                    }

                    var tags = appState.sharedPreferencesProvider.getCards();

                    if (sak4Controller.text.length != 2 ||
                        atqa4Controller.text.length != 5) {
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
                          content: Text(localizations.invalid_input),
                        ),
                      );
                    }

                    var tag = CardSave(
                      name: nameController.text,
                      sak: hexToBytes(sak4Controller.text)[0],
                      atqa: hexToBytes(atqa4Controller.text),
                      uid: uid4Controller.text,
                      tag: selectedType,
                      data: blocks,
                    );
                    tag.folderId = folderId;
                    tags.add(tag);
                    appState.sharedPreferencesProvider.setCards(tags);
                    appState.changesMade();
                    Navigator.pop(context);
                  },
                  child: Text(
                    localizations.save_as(localizations.x_byte_uid(4)),
                  ),
                ),
              ElevatedButton(
                onPressed: () async {
                  List<Uint8List> blocks = [];
                  int blockSize = isMifareClassic(selectedType) ? 16 : 4;

                  for (var i = 0; i < contents.length; i += blockSize) {
                    blocks.add(contents.sublist(i, i + blockSize));
                  }

                  var tags = appState.sharedPreferencesProvider.getCards();

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
                        content: Text(localizations.invalid_input),
                      ),
                    );
                  }

                  var tag = CardSave(
                    name: nameController.text,
                    sak: hexToBytes(sak7Controller.text)[0],
                    atqa: hexToBytes(atqa7Controller.text),
                    uid: uid7Controller.text,
                    tag: selectedType,
                    data: blocks,
                  );
                  tag.folderId = folderId;
                  tags.add(tag);
                  appState.sharedPreferencesProvider.setCards(tags);
                  appState.changesMade();
                  Navigator.pop(context);
                },
                child: Text(localizations.save_as(localizations.x_byte_uid(7))),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close the modal without saving
                },
                child: Text(localizations.cancel),
              ),
            ],
          );
        },
      );
    }
  }
}

/// Adds the folders and cards of a folder export to the saved cards, inside
/// [parentId] (the top level if null). Shows an error if [source] is not a
/// valid folder export.
Future<void> importCardFolder(
  BuildContext context,
  String source, {
  String? parentId,
}) async {
  final localizations = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final appState = context.read<ChameleonGUIState>();

  try {
    final bundle = CardFolderBundle.fromJson(source);
    final folders = appState.sharedPreferencesProvider.getCardFolders();
    final cards = appState.sharedPreferencesProvider.getCards();
    final idMap = <String, String>{};
    for (final imported in bundle.folders) {
      idMap[imported.id] = CardFolder(name: '').id;
    }
    for (final imported in bundle.folders) {
      folders.add(CardFolder(
        id: idMap[imported.id],
        name: imported.name,
        color: imported.color,
        parentId: imported.id == bundle.rootFolderId
            ? parentId
            : idMap[imported.parentId],
      ));
    }
    for (final imported in bundle.cards) {
      final copy = CardSave.fromJson(imported.toJson());
      copy.id = CardFolder(name: '').id;
      copy.folderId = idMap[imported.folderId];
      cards.add(copy);
    }
    appState.sharedPreferencesProvider.setCardFolders(folders);
    appState.sharedPreferencesProvider.setCards(cards);
    appState.changesMade();
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text(localizations.invalid_folder_export)),
    );
  }
}
