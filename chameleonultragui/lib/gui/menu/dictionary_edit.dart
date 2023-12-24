import 'package:flutter/material.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:chameleonultragui/helpers/general.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class DictionaryEditMenu extends StatefulWidget {
  final Dictionary dictionary;
  final bool isNew;

  const DictionaryEditMenu(
      {super.key, required this.dictionary, this.isNew = false});

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
    nameController = TextEditingController(text: widget.dictionary.name);
    keysController =
        TextEditingController(text: dictToString(widget.dictionary.keys));
    pickerColor = widget.dictionary.color;
    currentColor = widget.dictionary.color;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(localizations.edit_dictionary),
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
                    return localizations.please_enter_name;
                  }
                  return null;
                },
                decoration: InputDecoration(
                    labelText: localizations.name,
                    hintText: localizations.enter_dict_name,
                    prefix: Transform(
                      transform: Matrix4.translationValues(0, 7, 0),
                      child: IconButton(
                        icon: Icon(Icons.key, color: currentColor),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text('${localizations.pick_color}!'),
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
                                    child: Text(localizations.reset_default),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: Text(localizations.cancel),
                                  ),
                                  TextButton(
                                    child: Text(localizations.ok),
                                    onPressed: () {
                                      setState(
                                          () => currentColor = pickerColor);
                                      Navigator.pop(context);
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    )),
              ),
              TextFormField(
                maxLines: null,
                controller: keysController,
                style:
                    const TextStyle(fontFamily: 'RobotoMono', fontSize: 16.0),
                decoration: InputDecoration(
                  labelText: localizations.keys,
                  hintText: localizations.enter_dict_keys,
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
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Dictionary dict = Dictionary(
              name: nameController.text,
              keys: stringToDict(keysController.text),
              color: currentColor,
            );

            var dictionaries =
                appState.sharedPreferencesProvider.getDictionaries();
            List<Dictionary> output = [];

            if (widget.isNew) {
              output = dictionaries;
              output.add(dict);
            } else {
              for (var dictTest in dictionaries) {
                if (dictTest.id != widget.dictionary.id) {
                  output.add(dictTest);
                } else {
                  output.add(dict);
                }
              }
            }

            appState.sharedPreferencesProvider.setDictionaries(output);
            appState.changesMade();
            Navigator.pop(context);
          },
          child: Text(localizations.save),
        ),
      ],
    );
  }
}
