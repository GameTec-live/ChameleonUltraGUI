import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/ntag/general.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SlotEditMenu extends StatefulWidget {
  final String name;
  final bool isEnabled;
  final TagType slotType;
  final TagFrequency frequency;
  final int slot;
  final dynamic update;

  const SlotEditMenu(
      {Key? key,
      required this.name,
      required this.isEnabled,
      required this.slotType,
      required this.frequency,
      required this.slot,
      required this.update})
      : super(key: key);

  @override
  SlotEditMenuState createState() => SlotEditMenuState();
}

class SlotEditMenuState extends State<SlotEditMenu> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  TextEditingController nameController = TextEditingController();
  TextEditingController uidController = TextEditingController();
  TextEditingController sakController = TextEditingController();
  TextEditingController atqaController = TextEditingController();
  TextEditingController atsController = TextEditingController();
  TagType? selectedType;
  TagType previousTagType = TagType.unknown;
  EmulatorSettings? emulatorSettings;
  int detectionCount = 0;

  @override
  void initState() {
    super.initState();
    selectedType = widget.slotType;
    nameController.text = widget.name;
  }

  Future<void> updateInfo() async {
    var appState = context.watch<ChameleonGUIState>();
    if (previousTagType == selectedType ||
        isMifareClassic(previousTagType) && isMifareClassic(selectedType!)) {
      return;
    }

    await appState.communicator!.activateSlot(widget.slot);

    if (selectedType == TagType.em410X) {
      try {
        uidController.text =
            bytesToHexSpace(await appState.communicator!.getEM410XEmulatorID());
      } catch (_) {}
    } else if (isMifareClassic(selectedType!)) {
      try {
        CardData data = await appState.communicator!.mf1GetAntiCollData();
        uidController.text = bytesToHexSpace(data.uid);
        sakController.text = bytesToHex(u8ToBytes(data.sak));
        atqaController.text = bytesToHexSpace(data.atqa);
        atsController.text = bytesToHexSpace(data.ats);

        emulatorSettings =
            await appState.communicator!.getMf1EmulatorSettings();

        if (emulatorSettings!.isDetectionEnabled) {
          detectionCount = await appState.communicator!.getMf1DetectionCount();
        }
      } catch (_) {}
    }

    setState(() {
      previousTagType = selectedType!;
    });
  }

  Future<void> save() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    await appState.communicator!.activateSlot(widget.slot);
    if (widget.slotType != selectedType) {
      await appState.communicator!.setSlotType(widget.slot, selectedType!);
      if (!isMifareClassic(selectedType!) ||
          !(isMifareClassic(selectedType!) &&
              isMifareClassic(widget.slotType))) {
        await appState.communicator!
            .setDefaultDataToSlot(widget.slot, selectedType!);
      }
    }

    if (selectedType == TagType.em410X) {
      await appState.communicator!
          .setEM410XEmulatorID(hexToBytesSpace(uidController.text));
    } else if (isMifareClassic(selectedType!)) {
      var cardData = CardData(
          uid: hexToBytesSpace(uidController.text),
          atqa: hexToBytesSpace(atqaController.text),
          sak: bytesToU8(hexToBytesSpace(sakController.text)),
          ats: hexToBytesSpace(atsController.text));
      await appState.communicator!.setMf1AntiCollision(cardData);
    }

    await appState.communicator!
        .setSlotTagName(widget.slot, nameController.text, widget.frequency);
    await appState.communicator!.saveSlotData();

    widget.update(nameController.text, widget.frequency, selectedType);
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();

    return AlertDialog(
      title: Text(localizations.edit_slot_data),
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
              ),
              const SizedBox(height: 8),
              DropdownButton<TagType>(
                value: selectedType,
                items: [
                  ...getTagTypeByFrequency(widget.frequency),
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
                  if (newValue != TagType.unknown && !isNTAG(newValue!)) {
                    setState(() {
                      selectedType = newValue;
                    });
                  }
                },
              ),
              FutureBuilder(
                  future: updateInfo(),
                  builder: (BuildContext context, AsyncSnapshot snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !(previousTagType == selectedType ||
                            isMifareClassic(previousTagType) &&
                                isMifareClassic(selectedType!))) {
                      return const Column(
                          children: [CircularProgressIndicator()]);
                    } else if (snapshot.hasError) {
                      appState.connector!.performDisconnect();
                      return Text(
                          '${localizations.error}: ${snapshot.error.toString()}');
                    } else {
                      return Visibility(
                          visible: selectedType != TagType.unknown,
                          child: Column(children: [
                            Column(children: [
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: uidController,
                                decoration: InputDecoration(
                                    labelText: localizations.uid,
                                    hintText: localizations
                                        .enter_something(localizations.uid)),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return localizations.please_enter_something(
                                        localizations.uid);
                                  }
                                  if (!(value.replaceAll(" ", "").length ==
                                              14 ||
                                          value.replaceAll(" ", "").length ==
                                              8) &&
                                      chameleonTagToFrequency(selectedType ??
                                              widget.slotType) !=
                                          TagFrequency.lf) {
                                    return localizations.must_or(
                                        4, 7, localizations.uid);
                                  }
                                  if (value.replaceAll(" ", "").length != 10 &&
                                      chameleonTagToFrequency(selectedType ??
                                              widget.slotType) ==
                                          TagFrequency.lf) {
                                    return localizations.must_be(
                                        5, localizations.uid);
                                  }
                                  return null;
                                },
                              ),
                              Visibility(
                                  visible: chameleonTagToFrequency(
                                          selectedType ?? widget.slotType) !=
                                      TagFrequency.lf,
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 20),
                                      TextFormField(
                                        controller: sakController,
                                        decoration: InputDecoration(
                                            labelText: localizations.sak,
                                            hintText:
                                                localizations.enter_something(
                                                    localizations.sak)),
                                        validator: (value) {
                                          if (value == null ||
                                              value.isEmpty &&
                                                  chameleonTagToFrequency(
                                                          selectedType ??
                                                              widget
                                                                  .slotType) !=
                                                      TagFrequency.lf) {
                                            return localizations
                                                .please_enter_something(
                                                    localizations.sak);
                                          }
                                          if (value
                                                      .replaceAll(" ", "")
                                                      .length !=
                                                  2 &&
                                              chameleonTagToFrequency(
                                                      selectedType ??
                                                          widget.slotType) !=
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
                                            hintText:
                                                localizations.enter_something(
                                                    localizations.atqa)),
                                        validator: (value) {
                                          if (value == null ||
                                              value.isEmpty &&
                                                  chameleonTagToFrequency(
                                                          selectedType ??
                                                              widget
                                                                  .slotType) !=
                                                      TagFrequency.lf) {
                                            return localizations
                                                .please_enter_something(
                                                    localizations.atqa);
                                          }
                                          if (value
                                                      .replaceAll(" ", "")
                                                      .length !=
                                                  4 &&
                                              chameleonTagToFrequency(
                                                      selectedType ??
                                                          widget.slotType) !=
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
                                              hintText:
                                                  localizations.enter_something(
                                                      localizations.ats)),
                                          validator: (value) {
                                            if (value!
                                                        .replaceAll(" ", "")
                                                        .length %
                                                    2 !=
                                                0) {
                                              return localizations
                                                  .must_be_valid_hex;
                                            }
                                            return null;
                                          }),
                                      if (isMifareClassic(selectedType!) &&
                                          emulatorSettings != null)
                                        Column(children: [
                                          const SizedBox(height: 20),
                                          Text(
                                            localizations
                                                .mifare_classic_emulator_settings,
                                            textScaleFactor: 1.1,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(localizations.mode_gen1a),
                                          const SizedBox(height: 8),
                                          ToggleButtonsWrapper(
                                              items: [
                                                localizations.yes,
                                                localizations.no
                                              ],
                                              selectedValue:
                                                  emulatorSettings!.isGen1a
                                                      ? 0
                                                      : 1,
                                              onChange: (int index) async {
                                                await appState.communicator!
                                                    .setMf1Gen1aMode(index == 0
                                                        ? true
                                                        : false);
                                              }),
                                          const SizedBox(height: 8),
                                          Text(localizations.mode_gen2),
                                          const SizedBox(height: 8),
                                          ToggleButtonsWrapper(
                                              items: [
                                                localizations.yes,
                                                localizations.no
                                              ],
                                              selectedValue:
                                                  emulatorSettings!.isGen2
                                                      ? 0
                                                      : 1,
                                              onChange: (int index) async {
                                                await appState.communicator!
                                                    .setMf1Gen2Mode(index == 0
                                                        ? true
                                                        : false);
                                              }),
                                          const SizedBox(height: 8),
                                          Text(localizations.use_from_block),
                                          const SizedBox(height: 8),
                                          ToggleButtonsWrapper(
                                              items: [
                                                localizations.yes,
                                                localizations.no
                                              ],
                                              selectedValue:
                                                  emulatorSettings!.isAntiColl
                                                      ? 0
                                                      : 1,
                                              onChange: (int index) async {
                                                await appState.communicator!
                                                    .setMf1UseFirstBlockColl(
                                                        index == 0
                                                            ? true
                                                            : false);
                                              }),
                                          const SizedBox(height: 8),
                                          Text(localizations
                                              .collect_nonces('Mfkey32')),
                                          const SizedBox(height: 8),
                                          ToggleButtonsWrapper(
                                              items: [
                                                localizations.yes,
                                                localizations.no
                                              ],
                                              selectedValue: emulatorSettings!
                                                      .isDetectionEnabled
                                                  ? 0
                                                  : 1,
                                              onChange: (int index) async {
                                                await appState.communicator!
                                                    .setMf1DetectionStatus(
                                                        index == 0
                                                            ? true
                                                            : false);
                                              }),
                                          ...(emulatorSettings!
                                                  .isDetectionEnabled)
                                              ? [
                                                  ...(detectionCount == 0)
                                                      ? [
                                                          const SizedBox(
                                                              height: 8),
                                                          Text(
                                                              localizations
                                                                  .present_cham_reader_keys,
                                                              textScaleFactor:
                                                                  0.8)
                                                        ]
                                                      : [
                                                          const SizedBox(
                                                              height: 8),
                                                          Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                TextButton(
                                                                    onPressed:
                                                                        () {
                                                                      Navigator.pop(
                                                                          context);
                                                                      appState.forceMfkey32Page =
                                                                          true;
                                                                      appState
                                                                          .changesMade();
                                                                    },
                                                                    child: Row(
                                                                      children: [
                                                                        const Icon(
                                                                            Icons.lock_open),
                                                                        Text(localizations
                                                                            .recover_keys),
                                                                      ],
                                                                    )),
                                                              ]),
                                                        ],
                                                ]
                                              : [
                                                  const SizedBox(height: 8),
                                                  Text(
                                                      localizations
                                                          .ena_coll_recover_keys,
                                                      textScaleFactor: 0.8)
                                                ],
                                          const SizedBox(height: 8),
                                          Text(localizations.write_mode),
                                          const SizedBox(height: 8),
                                          ToggleButtonsWrapper(
                                              items: [
                                                localizations.normal,
                                                localizations.decline,
                                                localizations.deceive,
                                                localizations.shadow
                                              ],
                                              selectedValue: emulatorSettings!
                                                  .writeMode.value,
                                              onChange: (int index) async {
                                                if (index == 0) {
                                                  await appState.communicator!
                                                      .setMf1WriteMode(
                                                          MifareClassicWriteMode
                                                              .normal);
                                                } else if (index == 1) {
                                                  await appState.communicator!
                                                      .setMf1WriteMode(
                                                          MifareClassicWriteMode
                                                              .denied);
                                                } else if (index == 2) {
                                                  await appState.communicator!
                                                      .setMf1WriteMode(
                                                          MifareClassicWriteMode
                                                              .deceive);
                                                } else if (index == 3) {
                                                  await appState.communicator!
                                                      .setMf1WriteMode(
                                                          MifareClassicWriteMode
                                                              .shadow);
                                                }
                                              }),
                                        ]),
                                    ],
                                  )),
                            ])
                          ]));
                    }
                  })
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            await save();

            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(localizations.save),
        ),
      ],
    );
  }
}
