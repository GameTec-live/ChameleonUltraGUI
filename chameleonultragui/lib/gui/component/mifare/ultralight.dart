import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/services.dart';
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
  List<int> counters = [];
  String dumpName = "";
  String error = "";
  double progress = -1;

  static const int ulcReadablePages = 0x2C;

  bool get isUlc => widget.hfInfo.type == TagType.ultralightC;

  Future<void> readUlcCard({bool withKey = true}) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    setState(() {
      cardData = [];
      error = "";
      progress = -1;
      state = MifareUltralightState.read;
    });

    if (withKey) {
      Uint8List key = hexToBytes(keyController.text);

      Uint8List data;
      try {
        data = await appState.communicator!
            .mf0UlcReadPages(key, 0, ulcReadablePages);
      } catch (_) {
        data = Uint8List(0);
      }

      if (data.length < 4) {
        setState(() {
          progress = 0;
          cardData = [];
          error = localizations.invalid_password;
          state = MifareUltralightState.none;
        });
        return;
      }

      int pagesRead = data.length ~/ 4;
      for (int page = 0; page < pagesRead; page++) {
        cardData.add(Uint8List.fromList(data.sublist(page * 4, page * 4 + 4)));
      }

      if (cardData.length == ulcReadablePages) {
        Uint8List cardKey = mfUltralightSwapUlcKeyOrder(key);
        for (int i = 0; i < 4; i++) {
          cardData.add(Uint8List.fromList(cardKey.sublist(i * 4, i * 4 + 4)));
        }
      }
    } else {
      for (int page = 0; page < ulcReadablePages; page++) {
        Uint8List pageData = await appState.communicator!
            .send14ARaw(Uint8List.fromList([0x30, page]));
        if (pageData.isNotEmpty) {
          cardData.add(Uint8List.fromList(pageData.slice(0, 4).toList()));
        } else {
          cardData.add(Uint8List(0));
        }
        setState(() {
          progress = page / ulcReadablePages;
        });
      }

      if (!cardData.any((block) => block.isNotEmpty)) {
        setState(() {
          progress = 0;
          cardData = [];
          error = localizations.failed_to_read_block;
          state = MifareUltralightState.none;
        });
        return;
      }

      for (int i = 0; i < 4; i++) {
        cardData.add(Uint8List(4));
      }
    }

    setState(() {
      progress = 1;
      error = "";
      state = MifareUltralightState.save;
    });
  }

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

    bool hasValidData = false;
    for (var block in cardData) {
      if (block.isNotEmpty) {
        hasValidData = true;
      }
    }

    if (!hasValidData) {
      setState(() {
        progress = 0;
        cardData = [];
        error = localizations.failed_to_read_block;
        state = MifareUltralightState.none;
      });
      return;
    }

    version =
        bytesToHexSpace(await mfUltralightGetVersion(appState.communicator!));
    signature =
        bytesToHexSpace(await mfUltralightGetSignature(appState.communicator!));

    if (mfUltralightHasCounters(widget.hfInfo.type)) {
      counters = await mfUltralightReadAllCountersFromCard(
          appState.communicator!, widget.hfInfo.type);
    }

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
    for (var page = 0; page < cardData.length; page++) {
      if (cardData[page].isEmpty) {
        cardDump.addAll(Uint8List(4));
      } else {
        cardDump.addAll(cardData[page]);
      }
    }

    if (bin) {
      await FilePicker.saveFile(
        dialogTitle: '${localizations.output_file}:',
        fileName: '${widget.hfInfo.uid.replaceAll(" ", "")}.bin',
        bytes: Uint8List.fromList(cardDump),
      );
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
            ultralightCounters: counters,
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
            child: TextFormField(
              controller: keyController,
              decoration: InputDecoration(
                  labelText: localizations.key,
                  hintMaxLines: 4,
                  hintText: isUlc
                      ? ""
                      : localizations.enter_something(
                          localizations.ultralight_key_prompt)),
              inputFormatters: hexFormatter,
              validator: (value) => validateHex(value, localizations,
                  exactBytes: isUlc ? 16 : 4, fieldName: localizations.key),
            ),
          ),
          const SizedBox(height: 8),
          if (isUlc)
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      await readUlcCard(withKey: true);
                    }
                  },
                  child: Text(localizations.read_with_key),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async => {await readUlcCard(withKey: false)},
                  child: Text(localizations.read_without_key),
                ),
              ),
            ])
          else
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
          LinearProgressIndicator(value: progress < 0 ? null : progress),
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
