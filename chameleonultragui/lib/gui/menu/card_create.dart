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
  final String? targetFolderId;
  
  const CardCreateMenu({super.key, this.targetFolderId});

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

  TextEditingController hidTypeController = TextEditingController(text: '1');
  TextEditingController facilityCodeController = TextEditingController();
  TextEditingController issueLevelController = TextEditingController();
  TextEditingController oemController = TextEditingController();

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

    blocks[0] = mfClassicGenerateFirstBlock(uid, sak, atqa);

    return blocks;
  }

  List<Uint8List> generateMifareUltralightBlocks() {
    final uid = hexToBytes(uidController.text);

    final List<Uint8List> blocks =
        mfUltralightGenerateFirstBlocks(uid, selectedType);

    final totalBlocks = getBlockCountForTagType(selectedType);
    final cc = Uint8List(4);
    cc[0] = 0xE1;
    cc[1] = 0x10;
    cc[2] = (getMemorySizeForTagType(selectedType) ~/ 8) & 0xFF;
    cc[3] = 0x00;
    blocks.add(cc);

    for (int i = 4; i < totalBlocks; i++) {
      blocks.add(Uint8List(4));
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
                items: [
                  ...getTagTypesByFrequency(TagFrequency.hf),
                  ...getTagTypesByFrequency(TagFrequency.lf)
                ].map<DropdownMenuItem<TagType>>((TagType type) {
                  return DropdownMenuItem<TagType>(
                    value: type,
                    child: Text(
                      chameleonTagToString(type, localizations),
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

                      String cleanValue = value.replaceAll(" ", "");

                      if (isMifareUltralight(selectedType)) {
                        if (cleanValue.length != 14) {
                          return localizations.must_be(localizations.uid, "7");
                        }
                      } else if (chameleonTagToFrequency(selectedType) ==
                          TagFrequency.hf) {
                        if (cleanValue.length != 14 || cleanValue.length != 8) {
                          return localizations.must_or(
                              "4", "7", localizations.uid);
                        }
                      } else if (cleanValue.length != 10 &&
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
                      ])),
                  if (selectedType == TagType.hidProx)
                    Column(children: [
                      const SizedBox(height: 20),
                      DropdownButton<int>(
                        value: int.tryParse(hidTypeController.text) ?? 1,
                        items: List.generate(30, (index) => index + 1)
                            .map<DropdownMenuItem<int>>((int type) {
                          return DropdownMenuItem<int>(
                            value: type,
                            child: Text(getNameForHIDProxType(type)),
                          );
                        }).toList(),
                        onChanged: (int? newValue) {
                          if (newValue != null) {
                            setState(() {
                              hidTypeController.text = newValue.toString();
                            });
                          }
                        },
                        isExpanded: true,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: facilityCodeController,
                        decoration: InputDecoration(
                            labelText: localizations.facility_code,
                            hintText: localizations
                                .enter_something(localizations.facility_code)),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (value) {
                          int? fc = int.tryParse(value!);
                          if (fc == null || fc < 0 || fc > 4294967295) {
                            return localizations.must_be_between(
                                '0', '4,294,967,295');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: issueLevelController,
                        decoration: InputDecoration(
                            labelText: localizations.issue_level,
                            hintText: localizations
                                .enter_something(localizations.issue_level)),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (value) {
                          int? il = int.tryParse(value!);
                          if (il == null || il < 0 || il > 255) {
                            return localizations.must_be_between('0', '255');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: oemController,
                        decoration: InputDecoration(
                            labelText: "OEM",
                            hintText: localizations.enter_something('OEM')),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (value) {
                          int? oem = int.tryParse(value!);
                          if (oem == null || oem < 0 || oem > 65535) {
                            return localizations.must_be_between('0', '65,535');
                          }
                          return null;
                        },
                      ),
                    ])
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

            String finalUid;
            if (selectedType == TagType.hidProx) {
              int hidType = int.parse(hidTypeController.text);
              int facilityCode = int.parse(facilityCodeController.text);
              int issueLevel = int.parse(issueLevelController.text);
              int oem = int.parse(oemController.text);

              Uint8List uid =
                  hexToBytes(uidController.text.replaceAll(' ', ''));

              HIDCard hidCard = HIDCard(
                hidType: hidType,
                facilityCode: facilityCode,
                uid: uid,
                issueLevel: issueLevel,
                oem: oem,
              );

              finalUid = hidCard.toString();
            } else {
              finalUid = bytesToHexSpace(hexToBytes(uidController.text));
            }

            final sak = chameleonTagToFrequency(selectedType) == TagFrequency.lf
                ? 0
                : hexToBytes(sakController.text)[0];
            final atqa =
                chameleonTagToFrequency(selectedType) == TagFrequency.lf
                    ? Uint8List(0)
                    : hexToBytes(atqaController.text);
            final ats = chameleonTagToFrequency(selectedType) == TagFrequency.lf
                ? Uint8List(0)
                : hexToBytes(atsController.text);

            List<Uint8List> blocks =
                chameleonTagToFrequency(selectedType) == TagFrequency.lf
                    ? []
                    : isMifareUltralight(selectedType)
                        ? generateMifareUltralightBlocks()
                        : generateMifareClassicBlocks();

            var tag = CardSave(
                name: nameController.text,
                sak: sak,
                atqa: atqa,
                uid: finalUid,
                folderId: widget.targetFolderId,
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
          child: Text(localizations.create),
        ),
      ],
    );
  }
}
