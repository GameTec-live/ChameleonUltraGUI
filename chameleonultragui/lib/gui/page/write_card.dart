import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/card_list.dart';
import 'package:chameleonultragui/gui/component/card_recovery.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class WriteCardPage extends StatefulWidget {
  const WriteCardPage({super.key});

  @override
  WriteCardPageState createState() => WriteCardPageState();
}

class WriteCardPageState extends State<WriteCardPage> {
  HFCardInfo? hfInfo;
  MifareClassicInfo? mfcInfo;
  int step = 0;
  int progress = -1;
  CardSave? card;
  AbstractWriteHelper? baseHelper;
  AbstractWriteHelper? helper;

  Future<String?> cardSelectDialog(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var tags = appState.sharedPreferencesProvider.getCards();

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(cards: tags, onTap: onTap),
    );
  }

  Future<void> onTap(CardSave selectedCard, dynamic close) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    setState(() {
      card = selectedCard;
      baseHelper = AbstractWriteHelper.getClassByCardType(
          selectedCard.tag, appState, updateState);
    });

    if (baseHelper != null) {
      setState(() {
        helper = baseHelper!.getAvailableMethods()[0];
      });
    }

    close(context, selectedCard.name);
  }

  Future<void> detectMagicType() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    var localizations = AppLocalizations.of(context)!;

    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    for (final magicHelper in baseHelper!.getAvailableMethods()) {
      if (await magicHelper.isMagic(card)) {
        setState(() {
          helper = magicHelper;
        });

        appState.log!.i("Detected Magic card type: ${magicHelper.name}");
        scaffoldMessenger.hideCurrentSnackBar();
        var snackBar = SnackBar(
          content: Text(
              '${localizations.detected_magic_card_type}: ${helper!.name}'),
          action: SnackBarAction(
            label: localizations.close,
            onPressed: () {},
          ),
        );

        scaffoldMessenger.showSnackBar(snackBar);
        return;
      }
    }

    var snackBar = SnackBar(
      content: Text(localizations.failed_to_detect_magic_card_type),
      action: SnackBarAction(
        label: localizations.close,
        onPressed: () {},
      ),
    );

    scaffoldMessenger.showSnackBar(snackBar);
  }

  Future<void> prepareMifareClassic() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    CardData card = await appState.communicator!.scan14443aTag();
    bool isMifareClassic = false;

    try {
      isMifareClassic = await appState.communicator!.detectMf1Support();
    } catch (_) {}

    bool isMifareClassicEV1 = isMifareClassic
        ? (await appState.communicator!
            .mf1Auth(0x45, 0x61, gMifareClassicKeys[3]))
        : false;

    setState(() {
      hfInfo = HFCardInfo();
      mfcInfo = MifareClassicInfo();
    });

    if (isMifareClassic) {
      setState(() {
        mfcInfo!.recovery = helper!.getExtraData()[0];
      });
    }

    setState(() {
      hfInfo!.uid = bytesToHexSpace(card.uid);
      hfInfo!.sak = card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();
      hfInfo!.atqa = bytesToHexSpace(card.atqa);
      hfInfo!.ats =
          (card.ats.isNotEmpty) ? bytesToHexSpace(card.ats) : localizations.no;
      mfcInfo!.isEV1 = isMifareClassicEV1;
      mfcInfo!.type = isMifareClassic
          ? mfClassicGetType(card.atqa, card.sak)
          : MifareClassicType.none;
      mfcInfo!.state = (mfcInfo!.type != MifareClassicType.none)
          ? MifareClassicState.checkKeys
          : MifareClassicState.none;
      hfInfo!.tech = isMifareClassic
          ? "Mifare Classic ${mfClassicGetName(mfcInfo!.type)}${isMifareClassicEV1 ? " EV1" : ""}"
          : localizations.other;
    });
  }

  void updateState() {
    setState(() {
      mfcInfo = mfcInfo;
    });
  }

  void updateProgress(int writeProgress) {
    setState(() {
      progress = writeProgress;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.write_card),
      ),
      body: Column(
        children: [
          Center(
              child: Stepper(
            currentStep: step,
            onStepContinue: (step == 0 && card == null ||
                    step == 1 && baseHelper == null)
                ? null
                : () async {
                    if (step != 2) {
                      if (step == 1) {
                        await helper?.reset();

                        setState(() {
                          hfInfo = null;
                          mfcInfo = null;
                        });
                      }
                      setState(() {
                        step++;
                      });
                    } else if (helper != null &&
                        helper!.isReady() &&
                        progress == -1) {
                      SnackBar snackBar;
                      updateProgress(0);

                      if (await helper!.writeData(card!.data, updateProgress)) {
                        snackBar = SnackBar(
                          content: Text(localizations.magic_success_write),
                          action: SnackBarAction(
                            label: localizations.close,
                            onPressed: () {},
                          ),
                        );
                      } else {
                        snackBar = SnackBar(
                          content: Text(localizations.magic_failed_write),
                          action: SnackBarAction(
                            label: localizations.close,
                            onPressed: () {},
                          ),
                        );
                      }

                      scaffoldMessenger.hideCurrentSnackBar();
                      scaffoldMessenger.showSnackBar(snackBar);

                      updateProgress(-1);
                    }
                  },
            onStepCancel: step == 0
                ? null
                : () async {
                    setState(() {
                      step--;
                    });
                    if (step == 1) {
                      await helper?.reset();

                      setState(() {
                        hfInfo = null;
                        mfcInfo = null;
                      });
                    }
                  },
            steps: [
              Step(
                title: Text(localizations.select_saved_card_to_write),
                content: Card(
                  child: ListTile(
                    title: Row(children: [
                      FilterChip(
                        onSelected: (bool selected) {
                          cardSelectDialog(context);
                        },
                        avatar: (card != null)
                            ? CircleAvatar(
                                backgroundColor: Colors.transparent,
                                child: Icon(
                                    (chameleonTagToFrequency(card!.tag) ==
                                            TagFrequency.hf)
                                        ? Icons.credit_card
                                        : Icons.wifi,
                                    color: card!.color),
                              )
                            : null,
                        label: Text((card != null)
                            ? card!.name
                            : localizations.select_saved_card),
                      )
                    ]),
                  ),
                ),
                isActive: step >= 1,
              ),
              Step(
                title: Text(localizations.select_magic_card),
                content: Card(
                  child: ListTile(
                    title: (baseHelper != null)
                        ? Row(children: [
                            DropdownButton<AbstractWriteHelper>(
                              value: helper,
                              items: baseHelper!
                                  .getAvailableMethods()
                                  .map<DropdownMenuItem<AbstractWriteHelper>>(
                                      (AbstractWriteHelper helperClass) {
                                return DropdownMenuItem<AbstractWriteHelper>(
                                  value: helperClass,
                                  child: Text(helperClass.name),
                                );
                              }).toList(),
                              onChanged: (AbstractWriteHelper? helperClass) {
                                setState(() {
                                  helper = helperClass;
                                });
                              },
                            ),
                            if (baseHelper!.autoDetect)
                              ElevatedButton(
                                onPressed: () async {
                                  await detectMagicType();
                                },
                                child:
                                    Text(localizations.auto_detect_magic_card),
                              )
                          ])
                        : Text(localizations.writing_is_not_yet_supported),
                  ),
                ),
                isActive: step >= 2,
              ),
              Step(
                title: Text(localizations.write_data_to_magic_card),
                content: Card(
                  child: ListTile(
                    title: (progress == -1)
                        ? (helper != null && helper!.isReady())
                            ? Text(localizations.otp_magic_warning)
                            : (helper != null)
                                ? FutureBuilder(
                                    future: (hfInfo != null)
                                        ? Future.value([])
                                        : prepareMifareClassic(),
                                    builder: (BuildContext context,
                                        AsyncSnapshot snapshot) {
                                      if (hfInfo != null &&
                                          mfcInfo != null &&
                                          mfcInfo!.recovery != null) {
                                        return CardRecovery(
                                            hfInfo: hfInfo!,
                                            mfcInfo: mfcInfo!,
                                            allowSave: false);
                                      } else {
                                        return const Column(children: [
                                          CircularProgressIndicator()
                                        ]);
                                      }
                                    })
                                : Text(localizations.error)
                        : LinearProgressIndicator(
                            value: progress.toDouble() / 100),
                  ),
                ),
                isActive: step >= 3,
              ),
            ],
          )),
        ],
      ),
    );
  }
}
