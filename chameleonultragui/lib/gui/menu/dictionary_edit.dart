import 'package:flutter/material.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:chameleonultragui/helpers/general.dart';

class DictionaryEditMenu extends StatefulWidget {
  final ChameleonDictionary dict;

  const DictionaryEditMenu({Key? key, required this.dict}) : super(key: key);

  @override
  DictionaryEditMenuState createState() => DictionaryEditMenuState();
}

class DictionaryEditMenuState extends State<DictionaryEditMenu> {
  TextEditingController nameController = TextEditingController();
  TextEditingController keysController = TextEditingController();
  Color pickerColor = Colors.deepOrange;
  Color currentColor = Colors.deepOrange;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String bytesToHex(Uint8List bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  String dictToString(List<Uint8List> keys) {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key)}\n";
    }
    return output.trim();
  }

  List<Uint8List> stringToDict(String input) {
    List<Uint8List> keys = [];
    for (var key in input.split("\n")) {
      key = key.trim();
      if (key.length == 12 && isValidHexString(key)) {
        keys.add(hexToBytes(key));
      }
    }
    return keys;
  }

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.dict.name);
    keysController =
        TextEditingController(text: dictToString(widget.dict.keys));
    pickerColor = widget.dict.color;
    currentColor = widget.dict.color;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return AlertDialog(
      title: const Text('Edit Dictionary'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              TextFormField(
                controller: nameController,
                validator: (String? value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
                decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'Enter name of dictionary',
                    prefix: IconButton(
                      icon: Icon(Icons.nfc, color: currentColor),
                      onPressed: () async {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Pick a color!'),
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
                                  child: const Text('Ok'),
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
              TextFormField(
                maxLines: null,
                controller: keysController,
                decoration: const InputDecoration(
                  labelText: 'Keys',
                  hintText: 'Enter keys for dictionary',
                ),
              )
            ],
          ),
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
            if (!_formKey.currentState!.validate()) {
              return;
            }

            ChameleonDictionary dict = ChameleonDictionary(
              id: const Uuid().v4(),
              name: nameController.text,
              keys: stringToDict(keysController.text),
              color: currentColor,
            );

            var dictionaries =
                appState.sharedPreferencesProvider.getChameleonDictionaries();
            List<ChameleonDictionary> output = [];
            for (var dictTest in dictionaries) {
              if (dictTest.id != widget.dict.id) {
                output.add(dictTest);
              } else {
                output.add(dict);
              }
            }
            appState.sharedPreferencesProvider.setChameleonDictionaries(output);
            appState.changesMade();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
