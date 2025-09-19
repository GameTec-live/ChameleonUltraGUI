import 'package:flutter/material.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

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

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.dictionary.name);
    keysController = TextEditingController(text: widget.dictionary.toString());
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

            Dictionary dict = Dictionary.fromString(keysController.text,
                name: nameController.text, color: currentColor);
            dict.id = (widget.isNew ? null : widget.dictionary.id)!;

            if (dict.keys.isEmpty) {
              return;
            }

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
