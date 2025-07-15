import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class CardCreateMenu extends StatefulWidget {
  const CardCreateMenu({super.key});

  @override
  CardCreateMenuState createState() => CardCreateMenuState();
}

class CardCreateMenuState extends State<CardCreateMenu> {
  TagType selectedType = TagType.mifare1K;
  TextEditingController nameController = TextEditingController();
  TextEditingController uidController = TextEditingController();
  TextEditingController sakController = TextEditingController();
  TextEditingController atqaController = TextEditingController();
  TextEditingController atsController = TextEditingController();
  TextEditingController ultralightVersionController = TextEditingController();
  TextEditingController ultralightSignatureController = TextEditingController();
  Color pickerColor = Colors.deepOrange;
  Color currentColor = Colors.deepOrange;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  List<Uint8List> generateMifareClassicBlocks() {
    final uid = hexToBytes(uidController.text);
    final sak = hexToBytes(sakController.text)[0];
    final atqa = hexToBytes(atqaController.text);

    List<Uint8List> blocks = [];

    for (int sector = 0;
        sector <
            mfClassicGetSectorCount(
                chameleonTagTypeGetMfClassicType(selectedType));
        sector++) {
      for (int block = 0;
          block < mfClassicGetBlockCountBySector(sector) - 1;
          block++) {
        blocks.add(Uint8List(16));
      }

      blocks.add(Uint8List.fromList([
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0x07,
        0x80,
        0x69,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF
      ]));
    }

    final block0 = Uint8List(16);
    if (uid.length == 4) {
      block0.setAll(0, uid);
      block0[4] = calculateBcc(uid);
      block0[5] = sak + 0x80;
      block0.setAll(6, atqa);
      block0.setAll(8, [0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69]);
    } else if (uid.length == 7) {
      block0.setAll(0, uid);
      block0[7] = sak + 0x80;
      block0.setAll(8, atqa);
      block0.setAll(10, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    }

    blocks[0] = block0;

    return blocks;
  }

  List<Uint8List> generateMifareUltralightBlocks() {
    final uid = hexToBytes(uidController.text);

    final List<Uint8List> blocks = [];

    final block0 = Uint8List(4);
    block0.setAll(0, uid.sublist(0, 3));
    block0[3] =
        calculateBcc(Uint8List.fromList([0x88, uid[0], uid[1], uid[2]]));
    blocks.add(block0);

    final block1 = Uint8List(4);
    block1.setAll(0, uid.sublist(3, 7));
    blocks.add(block1);

    final block2 = Uint8List(4);
    block2[0] = calculateBcc(uid.sublist(3, 7));
    block2[1] = 0x48;
    block2[2] = 0x00;
    block2[3] = 0x00;
    blocks.add(block2);

    final totalBlocks = getBlockCountForTagType(selectedType);
    for (int i = 3; i < totalBlocks; i++) {
      if (i == 3) {
        final cc = Uint8List(4);
        cc[0] = 0xE1;
        cc[1] = 0x10;
        cc[2] = (getMemorySizeForTagType(selectedType) ~/ 8) & 0xFF;
        cc[3] = 0x00;
        blocks.add(cc);
      } else if (i >= totalBlocks - 5) {
        blocks.add(Uint8List(4));
      } else {
        blocks.add(Uint8List(4));
      }
    }

    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.create_card),
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
                    hintText: localizations.enter_name_of_card,
                    prefix: Transform(
                        transform: Matrix4.translationValues(0, 7, 0),
                        child: IconButton(
                          icon: Icon(
                              (chameleonTagToFrequency(selectedType) ==
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
                        ))),
              ),
              const SizedBox(height: 8),
              DropdownButton<TagType>(
                value: selectedType,
                items: getTagTypesByFrequency(TagFrequency.hf)
                    .map<DropdownMenuItem<TagType>>((TagType type) {
                  return DropdownMenuItem<TagType>(
                    value: type,
                    child: Text(
                      chameleonTagToString(type),
                    ),
                  );
                }).toList(),
                onChanged: (TagType? newValue) {
                  if (newValue! != TagType.unknown) {
                    setState(() {
                      selectedType = newValue;
                    });
                  }
                  appState.changesMade();
                },
              ),
              Visibility(
                visible: selectedType != TagType.unknown,
                child: Column(children: [
                  TextFormField(
                    controller: uidController,
                    decoration: InputDecoration(
                        labelText: localizations.uid,
                        hintText:
                            localizations.enter_something(localizations.uid)),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Fa-f: ]'))
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return localizations
                            .please_enter_something(localizations.uid);
                      }
                      if (!(value.replaceAll(" ", "").length == 14 ||
                              value.replaceAll(" ", "").length == 8 ||
                              value.replaceAll(" ", "").length == 20) &&
                          chameleonTagToFrequency(selectedType) !=
                              TagFrequency.lf) {
                        return localizations.must_or(
                            "4, 7", "10", localizations.uid);
                      }
                      if (value.replaceAll(" ", "").length != 10 &&
                          chameleonTagToFrequency(selectedType) ==
                              TagFrequency.lf) {
                        return localizations.must_be(5, localizations.uid);
                      }
                      return null;
                    },
                  ),
                  Visibility(
                      visible: chameleonTagToFrequency(selectedType) !=
                          TagFrequency.lf,
                      child: Column(children: [
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: sakController,
                          decoration: InputDecoration(
                              labelText: localizations.sak,
                              hintText: localizations
                                  .enter_something(localizations.sak)),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9A-Fa-f: ]'))
                          ],
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
                              return localizations.must_be(
                                  1, localizations.sak);
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: atqaController,
                          decoration: InputDecoration(
                              labelText: localizations.atqa,
                              hintText: localizations
                                  .enter_something(localizations.atqa)),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9A-Fa-f: ]'))
                          ],
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
                              return localizations.must_be(
                                  2, localizations.atqa);
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                            controller: atsController,
                            decoration: InputDecoration(
                                labelText: localizations.ats,
                                hintText: localizations
                                    .enter_something(localizations.ats)),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9A-Fa-f: ]'))
                            ],
                            validator: (value) {
                              if (value!.replaceAll(" ", "").length % 2 != 0) {
                                return localizations.must_be_valid_hex;
                              }
                              return null;
                            }),
                        if (isMifareUltralight(selectedType)) ...[ 
                          const SizedBox(height: 20),
                          TextFormField(
                              controller: ultralightVersionController,
                              decoration: InputDecoration(
                                  labelText: localizations.ultralight_version,
                                  hintText: localizations.enter_something(
                                      localizations.ultralight_version)),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9A-Fa-f: ]'))
                              ],
                              validator: (value) {
                                if (value!.replaceAll(" ", "").length % 2 !=
                                    0) {
                                  return localizations.must_be_valid_hex;
                                }

                                if (value.isNotEmpty &&
                                    value.replaceAll(" ", "").length != 16 &&
                                    isMifareUltralight(selectedType)) {
                                  return localizations.must_be(
                                      8, localizations.ultralight_version);
                                }

                                return null;
                              }),
                          const SizedBox(height: 20),
                          TextFormField(
                              controller: ultralightSignatureController,
                              decoration: InputDecoration(
                                  labelText: localizations.ultralight_signature,
                                  hintText: localizations.enter_something(
                                      localizations.ultralight_signature)),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9A-Fa-f: ]'))
                              ],
                              validator: (value) {
                                if (value!.replaceAll(" ", "").length % 2 !=
                                    0) {
                                  return localizations.must_be_valid_hex;
                                }
                                return null;
                              }),
                        ]
                      ]))
                ]),
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

            final uid = hexToBytes(uidController.text);
            final sak = chameleonTagToFrequency(selectedType) == TagFrequency.lf
                ? 0
                : hexToBytes(sakController.text)[0];
            final atqa = hexToBytes(atqaController.text);
            final ats = hexToBytes(atsController.text);

            final blocks = isMifareUltralight(selectedType)
                ? generateMifareUltralightBlocks()
                : generateMifareClassicBlocks();

            var tag = CardSave(
                name: nameController.text,
                sak: sak,
                atqa: atqa,
                uid: bytesToHexSpace(uid),
                extraData: CardSaveExtra(
                  ultralightSignature:
                      hexToBytes(ultralightSignatureController.text),
                  ultralightVersion:
                      hexToBytes(ultralightVersionController.text),
                ),
                tag: selectedType,
                data: blocks,
                color: currentColor,
                ats: ats);

            var tags = appState.sharedPreferencesProvider.getCards();
            tags.add(tag);

            appState.sharedPreferencesProvider.setCards(tags);
            appState.changesMade();
            Navigator.pop(context);
          },
          child: Text(localizations.create_card),
        ),
      ],
    );
  }
}