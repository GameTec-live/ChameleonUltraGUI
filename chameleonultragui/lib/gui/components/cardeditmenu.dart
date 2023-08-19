import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'dart:typed_data';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:uuid/uuid.dart';

class CardEditMenu extends StatefulWidget {
  final ChameleonTagSave tagSave;

  const CardEditMenu({Key? key, required this.tagSave}) : super(key: key);

  @override
  CardEditMenuState createState() => CardEditMenuState();
}

class CardEditMenuState extends State<CardEditMenu> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    ChameleonTag selectedType = widget.tagSave.tag;
    var uid = widget.tagSave.uid;
    var uidsak = widget.tagSave.sak;
    var uidatqa =
        Uint8List.fromList([widget.tagSave.atqa[0], widget.tagSave.atqa[1]]);
    final uidController = TextEditingController(text: uid);
    final sak4Controller =
        TextEditingController(text: bytesToHex(Uint8List.fromList([uidsak])));
    final atqa4Controller =
        TextEditingController(text: bytesToHexSpace(uidatqa));
    final nameController = TextEditingController(text: widget.tagSave.name);

    return AlertDialog(
      title: const Text('Edit card'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'Enter name of card'),
            ),
            DropdownButton<ChameleonTag>(
              value: selectedType,
              items: [
                ChameleonTag.mifare1K,
                ChameleonTag.mifare2K,
                ChameleonTag.mifare4K,
                ChameleonTag.mifareMini,
                ChameleonTag.ntag213,
                ChameleonTag.ntag215,
                ChameleonTag.ntag216,
                ChameleonTag.em410X,
              ].map<DropdownMenuItem<ChameleonTag>>((ChameleonTag type) {
                return DropdownMenuItem<ChameleonTag>(
                  value: type,
                  child: Text(
                    chameleonTagToString(type),
                  ),
                );
              }).toList(),
              onChanged: (ChameleonTag? newValue) {
                setState(() {
                  selectedType = newValue!;
                });
                appState.log.d('Changed card type to ${chameleonTagToString(selectedType)}');
                appState.changesMade(); // TODO: Make refreshing work
              },
            ),
            Column(children: [
              const SizedBox(height: 20),
              TextFormField(
                controller: uidController,
                decoration: const InputDecoration(
                    labelText: 'UID', hintText: 'Enter UID'),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: sak4Controller,
                decoration: const InputDecoration(
                    labelText: 'SAK', hintText: 'Enter SAK'),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: atqa4Controller,
                decoration: const InputDecoration(
                    labelText: 'ATQA', hintText: 'Enter ATQA'),
              ),
              const SizedBox(height: 40),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            // Delete old card
            var tags = appState.sharedPreferencesProvider.getChameleonTags();
            List<ChameleonTagSave> output = [];
            for (var tagTest in tags) {
              if (tagTest.id != widget.tagSave.id) {
                output.add(tagTest);
              }
            }
            appState.sharedPreferencesProvider.setChameleonTags(output);

            // Write new card
            tags = appState.sharedPreferencesProvider.getChameleonTags();
            var tag = ChameleonTagSave(
              id: const Uuid().v4(),
              name: nameController.text,
              sak: hexToBytes(sak4Controller.text.replaceAll(" ", ""))[0],
              atqa: hexToBytes(atqa4Controller.text.replaceAll(" ", "")),
              uid: uidController.text,
              tag: selectedType,
              data: widget.tagSave.data,
            );
            tags.add(tag);
            appState.sharedPreferencesProvider.setChameleonTags(tags);
            appState.changesMade();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
