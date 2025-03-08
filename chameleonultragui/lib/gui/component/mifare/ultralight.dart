import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

enum MifareUltralightState { none, read, save }

class MifareUltralightHelper extends StatefulWidget {
  final HFCardInfo hfInfo;
  final bool allowSave;

  const MifareUltralightHelper(
      {super.key, required this.hfInfo, this.allowSave = true});

  @override
  State<StatefulWidget> createState() => CardReaderState();
}

class CardReaderState extends State<MifareUltralightHelper> {
  TextEditingController keyController = TextEditingController();
  MifareUltralightState state = MifareUltralightState.none;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  List<Uint8List> cardData = [];
  String version = "";
  String signature = "";
  String dumpName = "";
  String error = "";
  double progress = -1;

  Future<void> readCard({bool withPassword = false}) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;
    Uint8List? pack;
    setState(() {
      cardData = [];
      error = "";
      state = MifareUltralightState.read;
    });

    for (var page = 0;
        page < mfUltralightGetPagesCount(widget.hfInfo.type);
        page++) {
      if (withPassword) {
        pack = await appState.communicator!.send14ARaw(
            Uint8List.fromList([0x1B, ...hexToBytes(keyController.text)]),
            keepRfField: true);
        if (pack.length < 2) {
          setState(() {
            state = MifareUltralightState.none;
            error = localizations.invalid_password;
          });
          return;
        }
      }

      Uint8List pageData = await appState.communicator!
          .send14ARaw(Uint8List.fromList([0x30, page]));
      if (pageData.isNotEmpty) {
        cardData.add(Uint8List.fromList(pageData.slice(0, 4).toList()));
      } else {
        cardData.add(Uint8List(0));
      }

      setState(() {
        progress = page / mfUltralightGetPagesCount(widget.hfInfo.type);
      });
    }

    version =
        bytesToHexSpace(await mfUltralightGetVersion(appState.communicator!));
    signature =
        bytesToHexSpace(await mfUltralightGetSignature(appState.communicator!));

    // Save password to dump if was used
    int passwordPage = mfUltralightGetPasswordPage(widget.hfInfo.type);
    if (passwordPage != 0 && withPassword) {
      cardData[passwordPage] = hexToBytes(keyController.text);
      cardData[passwordPage + 1] = Uint8List(4);
      for (var byte = 0; byte < pack!.length; byte++) {
        cardData[passwordPage + 1][byte] = pack[byte];
      }
    }

    setState(() {
      error = "";
      state = MifareUltralightState.save;
    });
  }

  Future<void> saveCard({bool bin = false}) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    List<int> cardDump = [];
    var localizations = AppLocalizations.of(context)!;
    for (var page = 0;
        page < mfUltralightGetPagesCount(widget.hfInfo.type);
        page++) {
      if (cardData[page].isEmpty) {
        cardDump.addAll(Uint8List(4));
      } else {
        cardDump.addAll(cardData[page]);
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
          tag: widget.hfInfo.type,
          data: cardData,
          extraData: CardSaveExtra(
            ultralightSignature: hexToBytes(signature),
            ultralightVersion: hexToBytes(version),
          ),
          ats: (widget.hfInfo.ats != localizations.no)
              ? hexToBytes(widget.hfInfo.ats)
              : Uint8List(0)));
      appState.sharedPreferencesProvider.setCards(tags);
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    return Column(
      children: [
        const SizedBox(height: 16),
        if (state == MifareUltralightState.none) ...[
          Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                TextFormField(
                  controller: keyController,
                  decoration: InputDecoration(
                      labelText: localizations.key,
                      hintMaxLines: 4,
                      hintText: localizations.enter_something(
                          localizations.ultralight_key_prompt)),
                  validator: (String? value) {
                    if (value!.isNotEmpty && !isValidHexString(value)) {
                      return localizations.must_be_valid_hex;
                    }

                    if (value.length != 8) {
                      return localizations.must_be(4, localizations.key);
                    }

                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () async => {await readCard(withPassword: true)},
                child: Text(localizations.read_with_key),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async => {await readCard(withPassword: false)},
                child: Text(localizations.read_without_key),
              ),
            ),
          ]),
        ],
        if (error != "") ...[
          const SizedBox(height: 16),
          ErrorMessage(errorMessage: error),
        ],
        if (state == MifareUltralightState.read) ...[
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8)
        ],
        if (state == MifareUltralightState.save)
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
              ])),
      ],
    );
  }
}
