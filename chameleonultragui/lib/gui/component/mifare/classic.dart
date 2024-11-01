import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/menu/dictionary_export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class MifareClassicHelper extends StatefulWidget {
  final HFCardInfo hfInfo;
  final MifareClassicInfo mfcInfo;
  final bool allowSave;

  const MifareClassicHelper(
      {super.key,
      required this.hfInfo,
      required this.mfcInfo,
      this.allowSave = true});

  @override
  State<StatefulWidget> createState() => CardReaderState();
}

class CardReaderState extends State<MifareClassicHelper> {
  String dumpName = "";
  bool skipDefaultDictionary = false;

  Future<void> exportFoundKeys() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return DictionaryExportMenu(keys: widget.mfcInfo.recovery!.validKeys);
      },
    );
  }

  Future<void> saveCard({bool bin = false, bool skipDump = false}) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    List<int> cardDump = [];
    var localizations = AppLocalizations.of(context)!;
    if (!skipDump) {
      for (var sector = 0;
          sector < mfClassicGetSectorCount(widget.mfcInfo.type);
          sector++) {
        for (var block = 0;
            block < mfClassicGetBlockCountBySector(sector);
            block++) {
          cardDump.addAll(widget.mfcInfo.recovery!
              .cardData[block + mfClassicGetFirstBlockCountBySector(sector)]);
        }
      }
    }

    if (bin) {
      try {
        await FileSaver.instance.saveAs(
            name: widget.hfInfo.uid.replaceAll(" ", ""),
            bytes: Uint8List.fromList(cardDump),
            ext: 'bin',
            mimeType: MimeType.other);
      } on UnimplementedError catch (_) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '${localizations.output_file}:',
          fileName: '${widget.hfInfo.uid.replaceAll(" ", "")}.bin',
        );

        if (outputFile != null) {
          var file = File(outputFile);
          await file.writeAsBytes(Uint8List.fromList(cardDump));
        }
      }
    } else {
      var tags = appState.sharedPreferencesProvider.getCards();
      tags.add(CardSave(
          uid: widget.hfInfo.uid,
          sak: hexToBytes(widget.hfInfo.sak)[0],
          atqa: hexToBytes(widget.hfInfo.atqa),
          name: dumpName,
          tag: (skipDump)
              ? TagType.mifare1K
              : mfClassicGetChameleonTagType(widget.mfcInfo.type),
          data: widget.mfcInfo.recovery!.cardData,
          ats: (widget.hfInfo.ats != localizations.no)
              ? hexToBytes(widget.hfInfo.ats)
              : Uint8List(0)));
      appState.sharedPreferencesProvider.setCards(tags);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    var localizations = AppLocalizations.of(context)!;
    final isSmallScreen = screenSize.width < 800;

    double checkmarkFontSize = isSmallScreen ? 12 : 16;
    double checkmarkSize = isSmallScreen ? 16 : 20;
    int checkmarkPerRow = (screenSize.width < 600) ? 8 : 16;

    var appState = context.watch<ChameleonGUIState>();
    widget.mfcInfo.recovery?.dictionaries =
        appState.sharedPreferencesProvider.getDictionaries();
    widget.mfcInfo.recovery?.dictionaries
        .insert(0, Dictionary(id: "", name: localizations.empty, keys: []));
    widget.mfcInfo.recovery?.selectedDictionary ??=
        widget.mfcInfo.recovery?.dictionaries[0];

    return Column(children: [
      const SizedBox(height: 16),
      Text(
        localizations.keys,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      if (widget.mfcInfo.recovery != null) ...[
        Row(
          children: [
            const Spacer(),
            KeyCheckMarks(
                checkMarks: widget.mfcInfo.recovery!.checkMarks,
                validKeys: widget.mfcInfo.recovery!.validKeys,
                fontSize: checkmarkFontSize,
                checkmarkSize: checkmarkSize,
                checkmarkCount: mfClassicGetSectorCount(widget.mfcInfo.type),
                checkmarkPerRow: checkmarkPerRow),
            const Spacer(),
          ],
        ),
        if (widget.mfcInfo.recovery?.error != "") ...[
          const SizedBox(height: 16),
          ErrorMessage(errorMessage: widget.mfcInfo.recovery!.error),
        ],
        const SizedBox(height: 12),
        if (widget.mfcInfo.recovery?.dumpProgress != 0) ...[
          LinearProgressIndicator(value: widget.mfcInfo.recovery?.dumpProgress),
          const SizedBox(height: 8)
        ],
        if (widget.mfcInfo.state == MifareClassicState.recovery ||
            widget.mfcInfo.state == MifareClassicState.recoveryOngoing)
          FittedBox(
              alignment: Alignment.topCenter,
              fit: BoxFit.scaleDown,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: (widget.mfcInfo.state ==
                              MifareClassicState.recovery)
                          ? () async {
                              setState(() {
                                widget.mfcInfo.state =
                                    MifareClassicState.recoveryOngoing;
                              });

                              await widget.mfcInfo.recovery?.recoverKeys();

                              if (widget.mfcInfo.recovery!.error.isNotEmpty) {
                                setState(() {
                                  widget.mfcInfo.state =
                                      MifareClassicState.recovery;
                                });
                                if (widget.mfcInfo.recovery!.error ==
                                    "no_keys_darkside") {
                                  setState(() {
                                    widget.mfcInfo.recovery?.error =
                                        localizations
                                            .recovery_error_no_keys_darkside;
                                  });
                                } else if (widget.mfcInfo.recovery!.error ==
                                    "not_supported") {
                                  setState(() {
                                    widget.mfcInfo.recovery?.error =
                                        localizations
                                            .recovery_error_no_supported;
                                  });
                                }
                              } else {
                                setState(() {
                                  widget.mfcInfo.state =
                                      MifareClassicState.dump;
                                });
                              }
                            }
                          : null,
                      child: Text(localizations.recover_keys),
                    ),
                    if (widget.allowSave) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (widget.mfcInfo.state ==
                                MifareClassicState.recovery)
                            ? () async {
                                setState(() {
                                  widget.mfcInfo.state =
                                      MifareClassicState.dumpOngoing;
                                });

                                try {
                                  await widget.mfcInfo.recovery?.dumpData();

                                  setState(() {
                                    widget.mfcInfo.recovery?.dumpProgress = 0;
                                    widget.mfcInfo.state =
                                        MifareClassicState.save;
                                  });
                                } catch (_) {
                                  setState(() {
                                    widget.mfcInfo.recovery?.error =
                                        localizations.recovery_error_dump_data;
                                    widget.mfcInfo.state =
                                        MifareClassicState.dump;
                                  });
                                }
                              }
                            : null,
                        child: Text(localizations.dump_partial_data),
                      )
                    ],
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        await exportFoundKeys();
                      },
                      child: Text(localizations.export_to_dictionary),
                    ),
                  ])),
        if (widget.mfcInfo.state == MifareClassicState.checkKeys ||
            widget.mfcInfo.state == MifareClassicState.checkKeysOngoing)
          Column(children: [
            Align(
                alignment: Alignment.center,
                child: SizedBox(
                    width: 275, // WIP: center without this
                    child: CheckboxListTile(
                      title: Text(localizations.skip_default_dictionary),
                      value: skipDefaultDictionary,
                      onChanged: (bool? newValue) {
                        setState(() {
                          skipDefaultDictionary = newValue!;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ))),
            const SizedBox(height: 8),
            Text(localizations.additional_key_dict),
            const SizedBox(height: 4),
            DropdownButton<String>(
              value: widget.mfcInfo.recovery?.selectedDictionary!.id,
              items: widget.mfcInfo.recovery?.dictionaries
                  .map<DropdownMenuItem<String>>((Dictionary dictionary) {
                return DropdownMenuItem<String>(
                  value: dictionary.id,
                  child: Text(
                      "${dictionary.name} (${dictionary.keys.length} ${localizations.keys.toLowerCase()})"),
                );
              }).toList(),
              onChanged: (String? newValue) {
                for (var dictionary in widget.mfcInfo.recovery!.dictionaries) {
                  if (dictionary.id == newValue) {
                    setState(() {
                      widget.mfcInfo.recovery?.selectedDictionary = dictionary;
                    });
                    break;
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: (widget.mfcInfo.state == MifareClassicState.checkKeys)
                  ? () async {
                      setState(() {
                        widget.mfcInfo.state =
                            MifareClassicState.checkKeysOngoing;
                      });

                      try {
                        await widget.mfcInfo.recovery!.checkKeys(
                            skipDefaultDictionary: skipDefaultDictionary);

                        if (widget.mfcInfo.recovery!.allKeysExists) {
                          // all keys exists
                          setState(() {
                            widget.mfcInfo.state = MifareClassicState.dump;
                          });
                        } else {
                          setState(() {
                            widget.mfcInfo.state = MifareClassicState.recovery;
                          });
                        }
                      } catch (_) {
                        for (var checkmark = 0; checkmark < 80; checkmark++) {
                          if (widget.mfcInfo.recovery?.checkMarks[checkmark] ==
                              ChameleonKeyCheckmark.checking) {
                            widget.mfcInfo.recovery?.checkMarks[checkmark] =
                                ChameleonKeyCheckmark.none;
                          }
                        }

                        try {
                          setState(() {
                            widget.mfcInfo.recovery?.checkMarks =
                                widget.mfcInfo.recovery!.checkMarks;
                            widget.mfcInfo.recovery?.error =
                                localizations.recovery_error_dict;
                            widget.mfcInfo.state = MifareClassicState.checkKeys;
                          });
                        } catch (_) {}
                      }
                    }
                  : null,
              child: Text(localizations.check_keys_dict),
            )
          ]),
        if ((widget.mfcInfo.state == MifareClassicState.dump ||
                widget.mfcInfo.state == MifareClassicState.dumpOngoing) &&
            widget.allowSave)
          FittedBox(
              alignment: Alignment.topCenter,
              fit: BoxFit.scaleDown,
              child: Row(children: [
                ElevatedButton(
                  onPressed: (widget.mfcInfo.state == MifareClassicState.dump)
                      ? () async {
                          setState(() {
                            widget.mfcInfo.state =
                                MifareClassicState.dumpOngoing;
                          });

                          try {
                            await widget.mfcInfo.recovery?.dumpData();

                            setState(() {
                              widget.mfcInfo.recovery?.dumpProgress = 0;
                              widget.mfcInfo.state = MifareClassicState.save;
                            });
                          } catch (_) {
                            setState(() {
                              widget.mfcInfo.recovery?.error =
                                  localizations.recovery_error_dump_data;
                              widget.mfcInfo.state = MifareClassicState.dump;
                            });
                          }
                        }
                      : null,
                  child: Text(localizations.dump_card),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    await exportFoundKeys();
                  },
                  child: Text(localizations.export_to_dictionary),
                ),
              ])),
      ],
      if (widget.mfcInfo.state == MifareClassicState.save && widget.allowSave)
        Center(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              ElevatedButton(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text(localizations.enter_name_of_card),
                        content: TextField(
                          onChanged: (value) {
                            setState(() {
                              dumpName = value;
                            });
                          },
                        ),
                        actions: [
                          ElevatedButton(
                            onPressed: () async {
                              await saveCard();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: Text(localizations.ok),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(
                                  context); // Close the modal without saving
                            },
                            child: Text(localizations.cancel),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: Text(localizations.save),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  await saveCard(bin: true);
                },
                child: Text(localizations.save_as(".bin")),
              ),
            ])),
    ]);
  }
}
