import 'package:chameleonultragui/helpers/sl1_native_projection.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/gui/component/card_auth_key_field.dart';

import 'dart:typed_data';

import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/menu/pages/dump_editor.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

  Future<void> saveCard({
    bool bin = false,
    bool skipDump = false,
    String? cardAuthKey,
  }) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    var localizations = AppLocalizations.of(context)!;
    Uint8List cardDump = Uint8List(0);
    if (!skipDump) {
      if (bin) {
        final card = CardSave(
          uid: widget.hfInfo.uid,
          name: dumpName,
          tag: mfClassicGetChameleonTagType(
          widget.mfcInfo.type),
          sak: hexToBytes(widget.hfInfo.sak)[0],
          atqa: hexToBytes(widget.hfInfo.atqa),
          data: widget.mfcInfo.isEV1
              ? widget.mfcInfo.recovery!.cardData.take(72).toList()
              : widget.mfcInfo.recovery!.cardData,
          ats: widget.hfInfo.ats == localizations.no
              ? Uint8List(0)
              : hexToBytes(widget.hfInfo.ats),
        );
        try {
          if (widget.mfcInfo.isEV1) {
            card.nativeClassicCoverage = widget.mfcInfo.recovery!.coverageFor(
              card,
            );
            card.data = card.nativeClassicCoverage!.project(
              fillKnownKeys: true,
            );
            cardDump = classicExportBytesForCard(card);
          } else {
            cardDump = Uint8List.fromList(
              widget.mfcInfo.recovery!
                  .profileFor(card)
                  .image()
                  .expand((b) => b)
                  .toList(),
            );
          }
        } catch (error) {
          if (context.mounted) {
            await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(localizations.classic_incomplete_image),
                content: Text(error.toString()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(localizations.close),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }
    }

    if (bin) {
      await FilePicker.saveFile(
        dialogTitle: '${localizations.output_file}:',
        fileName: '${widget.hfInfo.uid.replaceAll(" ", "")}.bin',
        bytes: cardDump,
      );
    } else {
      var tags = appState.sharedPreferencesProvider.getCards();
      final savedCard = CardSave(
          uid: widget.hfInfo.uid,
          sak: hexToBytes(widget.hfInfo.sak)[0],
          atqa: hexToBytes(widget.hfInfo.atqa),
          name: dumpName,
          tag: (skipDump)
              ? TagType.mifare1K
              : mfClassicGetChameleonTagType(widget.mfcInfo.type),
          data: widget.mfcInfo.isEV1
            ? widget.mfcInfo.recovery!.cardData.take(72).toList()
            : widget.mfcInfo.recovery!.cardData,
          extraData: CardSaveExtra(
            sl1CardAuthDetected: widget.mfcInfo.sl1CardAuthDetected,
          ),
          ats: (widget.hfInfo.ats != localizations.no)
              ? hexToBytes(widget.hfInfo.ats)
              : Uint8List(0));
      if (!skipDump && !widget.mfcInfo.isEV1) {
        savedCard.sl1Profile = widget.mfcInfo.recovery!.profileFor(savedCard);
        savedCard.data = Sl1NativeProjection.blocks(savedCard.sl1Profile!);
      }
      if (!skipDump && widget.mfcInfo.isEV1) {
        savedCard.nativeClassicCoverage = widget.mfcInfo.recovery!.coverageFor(
          savedCard,
        );
        savedCard.data = savedCard.nativeClassicCoverage!.project(
          fillKnownKeys: true,
        );
      }
      if (cardAuthKey != null) updateCardAuthKey(savedCard, cardAuthKey);
      tags.add(savedCard);
      appState.sharedPreferencesProvider.setCards(tags);
    }
  }

  Future<void> showSaveDialog() async {
    final localizations = AppLocalizations.of(context)!;
    var name = dumpName;
    var cardAuthKey = '';
    final form = GlobalKey<FormState>();
    String? error;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text(localizations.enter_name_of_card),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: name,
                    onChanged: (value) => name = value,
                    decoration: InputDecoration(labelText: localizations.name),
                  ),
                  if (!widget.mfcInfo.isEV1) ...[
                    const SizedBox(height: 16),
                    CardAuthKeyField(
                      initiallyVisible: widget.mfcInfo.sl1CardAuthDetected,
                      onChanged: (value) => cardAuthKey = value,
                    ),
                  ],
                  if (error != null) Text(error!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                try {
                  dumpName = name;
                  await saveCard(
                    cardAuthKey: widget.mfcInfo.isEV1 ? null : cardAuthKey,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) {
                    updateDialog(() => error = 'Could not save card: $e');
                  }
                }
              },
              child: Text(localizations.save),
            ),
          ],
        ),
      ),
    );
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
        appState.sharedPreferencesProvider.getDictionaries(keyLength: 12);
    widget.mfcInfo.recovery?.dictionaries
        .insert(0, Dictionary(id: "", name: localizations.empty, keys: []));
    widget.mfcInfo.recovery?.selectedDictionary ??=
        widget.mfcInfo.recovery?.dictionaries[0];

    WakelockPlus.toggle(
        enable: [
      MifareClassicState.checkKeysOngoing,
      MifareClassicState.recoveryOngoing,
      MifareClassicState.dumpOngoing
    ].contains(widget.mfcInfo.state));

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
                checkmarkCount: mfClassicGetSectorCount(widget.mfcInfo.type,
                    isEV1: widget.mfcInfo.isEV1),
                checkmarkPerRow: checkmarkPerRow,
                onCheckmarkChanged: (index, newValue) {
                  widget.mfcInfo.recovery!.checkMarks[index] = newValue;
                  widget.mfcInfo.recovery!.update();
                }),
            const Spacer(),
          ],
        ),
        if (widget.mfcInfo.recovery?.error != "") ...[
          const SizedBox(height: 16),
          ErrorMessage(errorMessage: widget.mfcInfo.recovery!.error),
        ],
        if (widget.mfcInfo.recovery?.state != "") ...[
          const SizedBox(height: 8),
          Text(widget.mfcInfo.recovery!.state),
        ],
        const SizedBox(height: 12),
        if (widget.mfcInfo.recovery?.dumpProgress != 0) ...[
          LinearProgressIndicator(value: widget.mfcInfo.recovery?.dumpProgress),
          const SizedBox(height: 8)
        ],
        if (widget.mfcInfo.recovery?.hardnestedProgress != null &&
            widget.mfcInfo.recovery?.error == "") ...[
          LinearProgressIndicator(
              value: widget.mfcInfo.recovery?.hardnestedProgress),
          const SizedBox(height: 12)
        ],
        if (widget.mfcInfo.recovery?.keyCheckProgress != null) ...[
          LinearProgressIndicator(
              value: widget.mfcInfo.recovery?.keyCheckProgress),
          const SizedBox(height: 12)
        ],
        if (widget.mfcInfo.state == MifareClassicState.recovery ||
            widget.mfcInfo.state == MifareClassicState.recoveryOngoing)
          _ResponsiveButtonGroup(children: [
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
                              } else {
                                setState(() {
                                  widget.mfcInfo.state =
                                      MifareClassicState.dump;
                                });
                              }
                            }
                          : null,
                      style: customCardButtonStyle(appState),
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
                                } catch (error) {
                                  setState(() {
                                    widget.mfcInfo.recovery?.error = error
                                    .toString();
                                    widget.mfcInfo.state =
                                        MifareClassicState.dump;
                                  });
                                }
                              }
                            : null,
                        style: customCardButtonStyle(appState),
                        child: Text(localizations.dump_partial_data),
                      )
                    ],
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        await exportFoundKeys();
                      },
                      style: customCardButtonStyle(appState),
                      child: Text(localizations.export_to_dictionary),
                    ),
          ]),
        if (widget.mfcInfo.state == MifareClassicState.checkKeys ||
            widget.mfcInfo.state == MifareClassicState.checkKeysOngoing)
          Column(children: [
            if (widget.mfcInfo.state == MifareClassicState.checkKeys)
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
                    for (var dictionary
                        in widget.mfcInfo.recovery!.dictionaries) {
                      if (dictionary.id == newValue) {
                        setState(() {
                          widget.mfcInfo.recovery?.selectedDictionary =
                              dictionary;
                        });
                        break;
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
              ]),
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
              style: customCardButtonStyle(appState),
              child: Text(localizations.check_keys_dict),
            )
          ]),
        if ((widget.mfcInfo.state == MifareClassicState.dump ||
                widget.mfcInfo.state == MifareClassicState.dumpOngoing) &&
            widget.allowSave)
          _ResponsiveButtonGroup(children: [
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
                          } catch (error) {
                            setState(() {
                              widget.mfcInfo.recovery?.error = error.toString();
                              widget.mfcInfo.state = MifareClassicState.dump;
                            });
                          }
                        }
                      : null,
                  style: customCardButtonStyle(appState),
                  child: Text(localizations.dump_card),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    await exportFoundKeys();
                  },
                  style: customCardButtonStyle(appState),
                  child: Text(localizations.export_to_dictionary),
                ),
          ]),
      ],
      if (widget.mfcInfo.state == MifareClassicState.save && widget.allowSave)
        _ResponsiveButtonGroup(
            centerOnly: true,
            children: [
              ElevatedButton(
                onPressed: () async {
                  final viewCard = CardSave(
                    uid: widget.hfInfo.uid,
                    sak: hexToBytes(widget.hfInfo.sak)[0],
                    atqa: hexToBytes(widget.hfInfo.atqa),
                    name: dumpName,
                    tag: mfClassicGetChameleonTagType(widget.mfcInfo.type),
                    data: widget.mfcInfo.recovery!.cardData,
                    ats: (widget.hfInfo.ats != localizations.no)
                        ? hexToBytes(widget.hfInfo.ats)
                        : Uint8List(0),
                  );
                  await showDialog(
                    context: context,
                    builder: (context) => DumpEditor(
                      cardSave: viewCard,
                      onSave: (data) {
                        // Apply edits back so a later save uses the
                        // modified dump without re-reading the card.
                        final changed = !classicBlockListsEqual(
                          widget.mfcInfo.recovery!.cardData,
                          data,
                        );
                        widget.mfcInfo.recovery!.cardData = data;
                        widget.mfcInfo.recovery!.readCoverageEdited =
                            widget.mfcInfo.recovery!.readCoverageEdited ||
                            changed;
                      },
                    ),
                  );
                  if (context.mounted) {
                    setState(() {});
                  }
                },
                style: customCardButtonStyle(appState),
                child: Text(localizations.view_dump),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: showSaveDialog,
                style: customCardButtonStyle(appState),
                child: Text(localizations.save),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  await saveCard(bin: true);
                },
                style: customCardButtonStyle(appState),
                child: Text(localizations.save_as(".bin")),
              ),
            ]),
    ]);
  }
}

class _ResponsiveButtonGroup extends StatelessWidget {
  final List<Widget> children;
  final bool centerOnly;

  const _ResponsiveButtonGroup({
    required this.children,
    this.centerOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).size.width < 800) {
      final buttons = children.where((child) => child is! SizedBox).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < buttons.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            buttons[index],
          ],
        ],
      );
    }

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );

    if (centerOnly) {
      return Center(child: row);
    }

    return FittedBox(
      alignment: Alignment.topCenter,
      fit: BoxFit.scaleDown,
      child: row,
    );
  }
}
