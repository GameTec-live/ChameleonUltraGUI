import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/card_list.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
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
  bool written = false;
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

    try {
      CardData card = await appState.communicator!.scan14443aTag();
      bool isMifareClassic = false;
      MifareClassicType mifareClassicType = MifareClassicType.none;

      try {
        isMifareClassic = await appState.communicator!.detectMf1Support();
        mifareClassicType = await mfClassicGetType(appState.communicator!);
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
        hfInfo!.ats = (card.ats.isNotEmpty)
            ? bytesToHexSpace(card.ats)
            : localizations.no;
        mfcInfo!.isEV1 = isMifareClassicEV1;
        mfcInfo!.type = mifareClassicType;
        mfcInfo!.state = (mfcInfo!.type != MifareClassicType.none)
            ? MifareClassicState.checkKeys
            : MifareClassicState.none;
        hfInfo!.tech = isMifareClassic
            ? "Mifare Classic ${mfClassicGetName(mfcInfo!.type)}${isMifareClassicEV1 ? " EV1" : ""}"
            : localizations.other;
      });
    } catch (_) {
      setState(() {
        hfInfo = HFCardInfo();
        mfcInfo = MifareClassicInfo();
      });

      setState(() {
        hfInfo!.cardExist = false;
      });
    }
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

  Future<void> writeCard() async {
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    var localizations = AppLocalizations.of(context)!;
    SnackBar snackBar;
    updateProgress(0);

    if (await helper!.writeData(card!, updateProgress)) {
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

    setState(() {
      written = true;
    });

    updateProgress(-1);
  }

  void onStepContinue() async {
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    if (appState.connector!.device == ChameleonDevice.lite) {
      showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(localizations.no_supported),
          content: Text(localizations.lite_no_read,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, localizations.ok),
              child: Text(localizations.ok),
            ),
          ],
        ),
      );

      return;
    }

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
    } else if (helper != null && helper!.isReady() && progress == -1) {
      SnackBar snackBar;
      updateProgress(0);

      if (!await helper!.isCompatible(card!)) {
        snackBar = SnackBar(
          content: Text(localizations.magic_incompatible_card),
          action: SnackBarAction(
            label: localizations.continue_anyway,
            onPressed: () async {
              await writeCard();
            },
          ),
        );

        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(snackBar);
      } else {
        await writeCard();
      }

      updateProgress(-1);
    }
  }

  void onStepBack() async {
    setState(() {
      written = false;
      step--;
    });

    if (step == 1) {
      await helper?.reset();

      setState(() {
        hfInfo = null;
        mfcInfo = null;
      });
    }
  }

  void onStepReset() async {
    setState(() {
      written = false;
      step = 0;
    });
  }

  List<Widget> createButtonsForStep(ControlsDetails details, int step) {
    var localizations = AppLocalizations.of(context)!;
    List<Widget> widgets = [];

    if (written) {
      widgets.add(TextButton(
        onPressed: (progress == -1) ? onStepContinue : null,
        child: Text(localizations.write_again),
      ));

      widgets.add(TextButton(
        onPressed: (progress == -1) ? onStepReset : null,
        child: Text(localizations.reset),
      ));
    } else {
      if (step == 0 || step == 1) {
        widgets.add(TextButton(
          onPressed:
              (step == 0 && card == null || step == 1 && baseHelper == null)
                  ? null
                  : onStepContinue,
          child: Text(localizations.next),
        ));
      }

      if (step == 2) {
        widgets.add(TextButton(
          onPressed: (helper != null && helper!.isReady() && progress == -1)
              ? onStepContinue
              : null,
          child: Text(localizations.write_data_to_magic_card),
        ));
      }

      if (step != 0) {
        widgets.add(TextButton(
          onPressed: onStepBack,
          child: Text(localizations.back),
        ));
      }
    }

    return widgets;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.write_card),
      ),
      body: SingleChildScrollView(
          child: Center(
              child: Stepper(
        physics: const ClampingScrollPhysics(),
        controlsBuilder: (BuildContext context, ControlsDetails details) {
          return Column(children: [
            const SizedBox(height: 8),
            Row(
              children: createButtonsForStep(details, step),
            )
          ]);
        },
        currentStep: step,
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
                    ? Wrap(
                        direction: Axis.horizontal,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
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
                            const SizedBox(width: 8),
                            if (baseHelper!.autoDetect)
                              TextButton(
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
                        ? (helper != null &&
                                helper!.name ==
                                    MifareClassicGen2WriteHelper.staticName &&
                                helper!.getExtraData()[1].isNotEmpty)
                            ? Text(
                                "${localizations.otp_magic_warning(localizations.write_data_to_magic_card)} ${localizations.some_blocks_failed_to_write}: ${helper!.getExtraData()[1].join(", ")}")
                            : Text(localizations.otp_magic_warning(
                                localizations.write_data_to_magic_card))
                        : (helper != null && helper!.writeWidgetSupported())
                            ? helper!.getWriteWidget(context,
                                [hfInfo, mfcInfo, prepareMifareClassic])
                            : Text(localizations.error)
                    : LinearProgressIndicator(value: progress.toDouble() / 100),
              ),
            ),
            isActive: step >= 3,
          ),
        ],
      ))),
    );
  }
}
