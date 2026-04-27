import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class CardEditMenu extends StatefulWidget {
  final CardSave tagSave;
  final bool isNew;

  const CardEditMenu({super.key, required this.tagSave, this.isNew = false});

  @override
  CardEditMenuState createState() => CardEditMenuState();
}

class CardEditMenuState extends State<CardEditMenu> {
  TagType selectedType = TagType.unknown;
  TextEditingController nameController = TextEditingController();
  TextEditingController uidController = TextEditingController();
  TextEditingController sakController = TextEditingController();
  TextEditingController atqaController = TextEditingController();
  TextEditingController atsController = TextEditingController();

  TextEditingController ultralightVersionController = TextEditingController();
  TextEditingController ultralightSignatureController = TextEditingController();
  List<TextEditingController> ultralightCounterControllers = [];

  TextEditingController hidTypeController = TextEditingController();
  TextEditingController facilityCodeController = TextEditingController();
  TextEditingController issueLevelController = TextEditingController();
  TextEditingController oemController = TextEditingController();

  Color pickerColor = Colors.deepOrange;
  Color currentColor = Colors.deepOrange;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String originalUid = '';
  String originalSak = '';
  String originalAtqa = '';

  @override
  void initState() {
    super.initState();
    selectedType = widget.tagSave.tag;
    uidController.text = widget.tagSave.uid;
    sakController.text = bytesToHexSpace(u8ToBytes(widget.tagSave.sak));
    atqaController.text = bytesToHexSpace(widget.tagSave.atqa);
    atsController.text = bytesToHexSpace(widget.tagSave.ats);
    ultralightVersionController.text =
        bytesToHexSpace(widget.tagSave.extraData.ultralightVersion);
    ultralightSignatureController.text =
        bytesToHexSpace(widget.tagSave.extraData.ultralightSignature);

    initCounterControllers();

    if (selectedType == TagType.hidProx) {
      initHIDFields();
    }

    nameController.text = widget.tagSave.name;
    pickerColor = widget.tagSave.color;
    currentColor = widget.tagSave.color;

    originalUid = widget.tagSave.uid;
    originalSak = bytesToHexSpace(u8ToBytes(widget.tagSave.sak));
    originalAtqa = bytesToHexSpace(widget.tagSave.atqa);
  }

  bool hasDataChanged() {
    return uidController.text != originalUid ||
        sakController.text != originalSak ||
        atqaController.text != originalAtqa;
  }

  Future<bool> showUpdateDataDialog(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;

    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(localizations.update_data_title),
              content: Text(localizations.update_data_message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(localizations.no),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(localizations.yes),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  List<Uint8List> updateCardData(List<Uint8List> originalData) {
    List<Uint8List> updatedData = List.from(originalData);

    if (isMifareClassic(selectedType)) {
      final uid = hexToBytes(uidController.text);
      final sak = hexToBytes(sakController.text)[0];
      final atqa = hexToBytes(atqaController.text);

      updatedData[0] = mfClassicGenerateFirstBlock(uid, sak, atqa);
    } else if (isMifareUltralight(selectedType)) {
      final uid = hexToBytes(uidController.text);
      final newBlocks = mfUltralightGenerateFirstBlocks(uid, selectedType);

      for (int i = 0; i < newBlocks.length && i < updatedData.length; i++) {
        updatedData[i] = newBlocks[i];
      }
    }

    return updatedData;
  }

  void initCounterControllers() {
    ultralightCounterControllers.clear();
    int counterCount = mfUltralightGetCounterCount(selectedType);

    for (int i = 0; i < counterCount; i++) {
      TextEditingController controller = TextEditingController();
      if (i < widget.tagSave.extraData.ultralightCounters.length) {
        controller.text =
            widget.tagSave.extraData.ultralightCounters[i].toString();
      } else {
        controller.text = '0';
      }
      ultralightCounterControllers.add(controller);
    }
  }

  void initHIDFields() {
    HIDCard hidCard = HIDCard.fromUID(widget.tagSave.uid);
    uidController.text = bytesToHexSpace(hidCard.uid);
    hidTypeController.text = hidCard.hidType.toString();
    facilityCodeController.text = hidCard.facilityCode.toString();
    issueLevelController.text = hidCard.issueLevel.toString();
    oemController.text = hidCard.oem.toString();
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
                validator: (value) => validateName(value, localizations),
                decoration: InputDecoration(
                    labelText: localizations.name,
                    hintText: localizations.enter_name_of_card,
                    prefix: Transform(
                        transform: Matrix4.translationValues(0, 7, 0),
                        child: IconButton(
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
                items: getTagTypes()
                    .map<DropdownMenuItem<TagType>>((TagType type) {
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
                      initCounterControllers();
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
                    inputFormatters: hexFormatter,
                    validator: (value) =>
                        validateUid(value, localizations, selectedType),
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
                          inputFormatters: hexFormatter,
                          validator: (value) =>
                              chameleonTagToFrequency(selectedType) ==
                                      TagFrequency.lf
                                  ? null
                                  : validateHex(value, localizations,
                                      exactBytes: 1,
                                      fieldName: localizations.sak,
                                      required: true),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: atqaController,
                          decoration: InputDecoration(
                              labelText: localizations.atqa,
                              hintText: localizations
                                  .enter_something(localizations.atqa)),
                          inputFormatters: hexFormatter,
                          validator: (value) =>
                              chameleonTagToFrequency(selectedType) ==
                                      TagFrequency.lf
                                  ? null
                                  : validateHex(value, localizations,
                                      exactBytes: 2,
                                      fieldName: localizations.atqa,
                                      required: true),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                            controller: atsController,
                            decoration: InputDecoration(
                                labelText: localizations.ats,
                                hintText: localizations
                                    .enter_something(localizations.ats)),
                            inputFormatters: hexFormatter,
                            validator: (value) =>
                                validateHex(value, localizations)),
                        if (isMifareUltralight(selectedType)) ...[
                          const SizedBox(height: 20),
                          TextFormField(
                              controller: ultralightVersionController,
                              decoration: InputDecoration(
                                  labelText: localizations.ultralight_version,
                                  hintText: localizations.enter_something(
                                      localizations.ultralight_version)),
                              inputFormatters: hexFormatter,
                              validator: (value) => validateHex(
                                  value, localizations,
                                  exactBytes: 8,
                                  fieldName: localizations.ultralight_version)),
                          const SizedBox(height: 20),
                          TextFormField(
                              controller: ultralightSignatureController,
                              decoration: InputDecoration(
                                  labelText: localizations.ultralight_signature,
                                  hintText: localizations.enter_something(
                                      localizations.ultralight_signature)),
                              inputFormatters: hexFormatter,
                              validator: (value) =>
                                  validateHex(value, localizations)),
                          if (mfUltralightHasCounters(selectedType)) ...[
                            const SizedBox(height: 20),
                            ...ultralightCounterControllers
                                .asMap()
                                .entries
                                .map((entry) {
                              int index = entry.key;
                              TextEditingController controller = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TextFormField(
                                  controller: controller,
                                  decoration: InputDecoration(
                                      labelText: localizations
                                          .ultralight_counter(index),
                                      hintText: localizations
                                          .ultralight_counter_value),
                                  validator: (value) => validateIntRange(
                                      value, localizations,
                                      min: 0,
                                      max: 16777215,
                                      emptyMessage:
                                          localizations.counter_value_empty),
                                ),
                              );
                            }),
                          ],
                        ]
                      ])),
                  if (selectedType == TagType.hidProx)
                    Column(children: [
                      const SizedBox(height: 20),
                      DropdownButton<int>(
                        value: int.tryParse(hidTypeController.text) ?? 1,
                        items: getHidProxTypeOptions()
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
                        validator: (value) => validateIntRange(
                            value, localizations,
                            min: 0, max: 4294967295),
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
                        validator: (value) => validateIntRange(
                            value, localizations,
                            min: 0, max: 255),
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
                        validator: (value) => validateIntRange(
                            value, localizations,
                            min: 0, max: 65535),
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
          onPressed: () async {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            List<Uint8List> cardData = widget.tagSave.data;

            if (hasDataChanged() &&
                (isMifareClassic(selectedType) ||
                    isMifareUltralight(selectedType))) {
              bool shouldUpdateData = await showUpdateDataDialog(context);
              if (shouldUpdateData) {
                cardData = updateCardData(widget.tagSave.data);
              }
            }

            String finalUid;
            if (selectedType == TagType.hidProx) {
              try {
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
              } catch (e) {
                finalUid = bytesToHexSpace(hexToBytes(uidController.text));
              }
            } else {
              finalUid = bytesToHexSpace(hexToBytes(uidController.text));
            }

            var tag = CardSave(
                id: widget.tagSave.id,
                name: nameController.text,
                sak: chameleonTagToFrequency(selectedType) == TagFrequency.lf
                    ? widget.tagSave.sak
                    : hexToBytes(sakController.text)[0],
                atqa: hexToBytes(atqaController.text),
                uid: finalUid,
                extraData: CardSaveExtra(
                  ultralightSignature:
                      hexToBytes(ultralightSignatureController.text),
                  ultralightVersion:
                      hexToBytes(ultralightVersionController.text),
                  ultralightCounters: ultralightCounterControllers
                      .map((controller) => int.tryParse(controller.text) ?? 0)
                      .toList(),
                ),
                tag: selectedType,
                data: cardData,
                color: currentColor,
                ats: hexToBytes(atsController.text));

            var tags = appState.sharedPreferencesProvider.getCards();
            var index =
                tags.indexWhere((element) => element.id == widget.tagSave.id);

            if (index != -1) {
              tags[index] = tag;
            }

            appState.sharedPreferencesProvider.setCards(tags);
            appState.changesMade();
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
