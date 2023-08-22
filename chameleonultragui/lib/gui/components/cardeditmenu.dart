import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'dart:typed_data';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class CardEditMenu extends StatefulWidget {
  final ChameleonTagSave tagSave;

  const CardEditMenu({Key? key, required this.tagSave}) : super(key: key);

  @override
  CardEditMenuState createState() => CardEditMenuState();
}

class CardEditMenuState extends State<CardEditMenu> {
  ChameleonTag selectedType = ChameleonTag.unknown;
  String uid = "";
  int uidsak = 0;
  Uint8List uidatqa = Uint8List.fromList([]);
  TextEditingController uidController = TextEditingController();
  TextEditingController sak4Controller = TextEditingController();
  TextEditingController atqa4Controller = TextEditingController();
  TextEditingController nameController = TextEditingController();
  Color pickerColor = Colors.deepOrange;
  Color currentColor = Colors.deepOrange;

  @override
  void initState() {
    super.initState();
    selectedType = widget.tagSave.tag;
    uid = widget.tagSave.uid;
    uidsak = widget.tagSave.sak;
    uidatqa = Uint8List.fromList(widget.tagSave.atqa);
    uidController = TextEditingController(text: uid);
    sak4Controller =
        TextEditingController(text: bytesToHex(Uint8List.fromList([uidsak])));
    atqa4Controller = TextEditingController(text: bytesToHexSpace(uidatqa));
    nameController = TextEditingController(text: widget.tagSave.name);
    pickerColor = widget.tagSave.color;
    currentColor = widget.tagSave.color;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return AlertDialog(
      title: const Text('Edit card'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextFormField(
              controller: nameController,
              decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'Enter name of card',
                  prefix: IconButton(
                    icon: Icon(Icons.nfc, color: currentColor),
                    onPressed: () async {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Pick a color'),
                            content: SingleChildScrollView(
                              child: ColorPicker(
                                pickerColor: pickerColor,
                                onColorChanged: (Color color) {
                                  setState(() {
                                    pickerColor = color;
                                  });
                                },
                                pickerAreaHeightPercent: 0.8,
                              ),
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  setState(() => currentColor =
                                      pickerColor = Colors.deepOrange);
                                  Navigator.pop(context);
                                },
                                child: const Text('Reset to default'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                child: const Text('OK'),
                                onPressed: () {
                                  setState(() => currentColor = pickerColor);
                                  Navigator.pop(context);
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  )),
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
                appState.changesMade();
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

            /*ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return HexEdit(data: widget.tagSave.data);
                  },
                );
              },
              child: const Text("Edit data"),
            ),*/ //TODO: Make Hex editor
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
              color: currentColor,
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
