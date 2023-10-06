import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'dart:typed_data';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CardEditMenu extends StatefulWidget {
  final CardSave tagSave;

  const CardEditMenu({Key? key, required this.tagSave}) : super(key: key);

  @override
  CardEditMenuState createState() => CardEditMenuState();
}

class CardEditMenuState extends State<CardEditMenu> {
  TagType selectedType = TagType.unknown;
  String uid = "";
  int sak = 0;
  Uint8List atqa = Uint8List.fromList([]);
  Uint8List ats = Uint8List.fromList([]);
  TextEditingController uidController = TextEditingController();
  TextEditingController sakController = TextEditingController();
  TextEditingController atqaController = TextEditingController();
  TextEditingController nameController = TextEditingController();
  TextEditingController atsController = TextEditingController();
  Color pickerColor = Colors.deepOrange;
  Color currentColor = Colors.deepOrange;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    selectedType = widget.tagSave.tag;
    uid = widget.tagSave.uid;
    sak = widget.tagSave.sak;
    ats = widget.tagSave.ats;
    atqa = Uint8List.fromList(widget.tagSave.atqa);
    uidController = TextEditingController(text: uid);
    sakController =
        TextEditingController(text: bytesToHexSpace(Uint8List.fromList([sak])));
    atqaController = TextEditingController(text: bytesToHexSpace(atqa));
    atsController = TextEditingController(text: bytesToHexSpace(ats));
    nameController = TextEditingController(text: widget.tagSave.name);
    pickerColor = widget.tagSave.color;
    currentColor = widget.tagSave.color;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.edit_card),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              TextFormField(
                controller: nameController,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return localizations.please_enter_name;
                  }
                  if (value.length > 19) {
                    return localizations.too_long_name;
                  }
                  return null;
                },
                decoration: InputDecoration(
                    labelText: localizations.name,
                    hintText: localizations.enter_name,
                    prefix: IconButton(
                      icon: Icon(
                          (chameleonTagToFrequency(widget.tagSave.tag) ==
                                  TagFrequency.hf)
                              ? Icons.credit_card
                              : Icons.wifi,
                          color: currentColor),
                      onPressed: () async {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text(localizations.pick_color),
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
              DropdownButton<TagType>(
                value: selectedType,
                items: [
                  TagType.mifare1K,
                  TagType.mifare2K,
                  TagType.mifare4K,
                  TagType.mifareMini,
                  TagType.ntag213,
                  TagType.ntag215,
                  TagType.ntag216,
                  TagType.em410X,
                  TagType.unknown
                ].map<DropdownMenuItem<TagType>>((TagType type) {
                  return DropdownMenuItem<TagType>(
                    value: type,
                    child: Text(
                      chameleonTagToString(type),
                    ),
                  );
                }).toList(),
                onChanged: (TagType? newValue) {
                  if (newValue != TagType.unknown) {
                    setState(() {
                      selectedType = newValue!;
                    });
                  }
                  appState.changesMade();
                },
              ),
              Column(children: [
                const SizedBox(height: 20),
                TextFormField(
                  controller: uidController,
                  decoration: InputDecoration(
                      labelText: localizations.uid,
                      hintText:
                          localizations.enter_something(localizations.uid)),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return localizations
                          .please_enter_something(localizations.uid);
                    }
                    if (!(value.replaceAll(" ", "").length == 14 ||
                            value.replaceAll(" ", "").length == 8) &&
                        chameleonTagToFrequency(selectedType) !=
                            TagFrequency.lf) {
                      return localizations.must_or(4, 7, localizations.uid);
                    }
                    if (value.replaceAll(" ", "").length != 10 &&
                        chameleonTagToFrequency(selectedType) ==
                            TagFrequency.lf) {
                      return localizations.must_be(5, localizations.uid);
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Visibility(
                  visible:
                      chameleonTagToFrequency(selectedType) != TagFrequency.lf,
                  child: TextFormField(
                    controller: sakController,
                    decoration: InputDecoration(
                        labelText: localizations.sak,
                        hintText:
                            localizations.enter_something(localizations.sak)),
                    validator: (value) {
                      if (value == null ||
                          value.isEmpty &&
                              chameleonTagToFrequency(selectedType) !=
                                  TagFrequency.lf) {
                        return localizations
                            .please_enter_something(localizations.sak);
                      }
                      if (value.replaceAll(" ", "").length != 2 &&
                          chameleonTagToFrequency(selectedType) !=
                              TagFrequency.lf) {
                        return localizations.must_be(1, localizations.sak);
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Visibility(
                  visible:
                      chameleonTagToFrequency(selectedType) != TagFrequency.lf,
                  child: TextFormField(
                    controller: atqaController,
                    decoration: InputDecoration(
                        labelText: localizations.atqa,
                        hintText:
                            localizations.enter_something(localizations.atqa)),
                    validator: (value) {
                      if (value == null ||
                          value.isEmpty &&
                              chameleonTagToFrequency(selectedType) !=
                                  TagFrequency.lf) {
                        return localizations
                            .please_enter_something(localizations.atqa);
                      }
                      if (value.replaceAll(" ", "").length != 4 &&
                          chameleonTagToFrequency(selectedType) !=
                              TagFrequency.lf) {
                        return localizations.must_be(2, localizations.atqa);
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Visibility(
                  visible:
                      chameleonTagToFrequency(selectedType) != TagFrequency.lf,
                  child: TextFormField(
                    controller: atsController,
                    decoration: InputDecoration(
                        labelText: localizations.ats,
                        hintText:
                            localizations.enter_something(localizations.ats)),
                  ),
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

            var tag = CardSave(
                id: widget.tagSave.uid,
                name: nameController.text,
                sak: chameleonTagToFrequency(selectedType) == TagFrequency.lf
                    ? widget.tagSave.sak
                    : hexToBytes(sakController.text.replaceAll(" ", ""))[0],
                atqa: hexToBytes(atqaController.text.replaceAll(" ", "")),
                uid: uidController.text,
                tag: selectedType,
                data: widget.tagSave.data,
                color: currentColor,
                ats: hexToBytes(atsController.text.replaceAll(" ", "")));

            var tags = appState.sharedPreferencesProvider.getCards();
            List<CardSave> output = [];
            for (var tagTest in tags) {
              if (tagTest.id != widget.tagSave.id) {
                output.add(tagTest);
              } else {
                output.add(tag);
              }
            }

            appState.sharedPreferencesProvider.setCards(output);
            appState.changesMade();
            Navigator.pop(context);
          },
          child: Text(localizations.save),
        ),
      ],
    );
  }
}
