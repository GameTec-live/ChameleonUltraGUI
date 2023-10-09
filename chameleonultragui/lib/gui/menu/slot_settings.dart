import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SlotSettings extends StatefulWidget {
  final int slot;
  final dynamic refresh;

  const SlotSettings({super.key, required this.slot, required this.refresh});

  @override
  SlotSettingsState createState() => SlotSettingsState();
}

class SlotSettingsState extends State<SlotSettings> {
  bool isRun = false;
  bool isEnabled = false;
  late bool isDetection;
  late int detectionCount;
  late bool isGen1a;
  late bool isGen2;
  late bool isAntiColl;
  late MifareClassicWriteMode writeMode;
  String hfName = "";
  String lfName = "";

  @override
  void initState() {
    super.initState();
  }

  Future<void> fetchInfo() async {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    if (hfName.isEmpty) {
      try {
        hfName = (await appState.communicator!
                .getSlotTagName(widget.slot, TagFrequency.hf))
            .trim();
      } catch (_) {}

      if (hfName.isEmpty) {
        hfName = localizations.empty;
      }

      setState(() {});
    }

    if (lfName.isEmpty) {
      try {
        lfName = (await appState.communicator!
                .getSlotTagName(widget.slot, TagFrequency.lf))
            .trim();
      } catch (_) {}

      if (lfName.isEmpty) {
        lfName = localizations.empty;
      }

      setState(() {});
    }

    if (!isRun) {
      await appState.communicator!.activateSlot(widget.slot);
      var enabledSlots = await appState.communicator!.getEnabledSlots();
      isEnabled = enabledSlots[widget.slot].$1 || enabledSlots[widget.slot].$2;
      var data = (await appState.communicator!.getMf1EmulatorConfig());
      isDetection = data.$1;
      if (isDetection) {
        detectionCount = await appState.communicator!.getMf1DetectionCount();
      } else {
        detectionCount = 0;
      }
      isGen1a = data.$2;
      isGen2 = data.$3;
      isAntiColl = data.$4;
      writeMode = data.$5;
      isRun = true;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return FutureBuilder(
        future: fetchInfo(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !isRun) {
            return AlertDialog(
                title: Text(localizations.slot_settings),
                content: const SingleChildScrollView(
                    child: Column(children: [CircularProgressIndicator()])));
          } else if (snapshot.hasError) {
            appState.connector!.performDisconnect();
            return AlertDialog(
                title: Text(localizations.slot_settings),
                content: Text(
                    '${localizations.error}: ${snapshot.error.toString()}'));
          } else {
            return AlertDialog(
                title: Text(localizations.slot_settings),
                content: SingleChildScrollView(
                    child: Column(children: [
                  Row(
                    children: [
                      Text('${localizations.hf}:'),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton(
                        onPressed: null,
                        child: Text(hfName),
                      )),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          await appState.communicator!
                              .deleteSlotInfo(widget.slot, TagFrequency.hf);
                          await appState.communicator!.setSlotTagName(
                              widget.slot,
                              localizations.empty,
                              TagFrequency.hf);
                          await appState.communicator!.saveSlotData();

                          setState(() {
                            hfName = "";
                          });

                          widget.refresh(widget.slot);
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${localizations.lf}:'),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton(
                        onPressed: null,
                        child: Text(lfName),
                      )),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          await appState.communicator!
                              .deleteSlotInfo(widget.slot, TagFrequency.lf);
                          await appState.communicator!.setSlotTagName(
                              widget.slot,
                              localizations.empty,
                              TagFrequency.lf);
                          await appState.communicator!.saveSlotData();

                          setState(() {
                            lfName = "";
                          });

                          widget.refresh(widget.slot);
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(localizations.slot_status),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: [localizations.enabled, localizations.disabled],
                      selectedValue: isEnabled ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.enableSlot(widget.slot,
                            TagFrequency.hf, index == 0 ? true : false);
                        await appState.communicator!.enableSlot(widget.slot,
                            TagFrequency.lf, index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 16),
                  Text(
                    localizations.mifare_classic_emulator_settings,
                    textScaleFactor: 1.1,
                  ),
                  const SizedBox(height: 8),
                  Text(localizations.mode_gen1a),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: [localizations.yes, localizations.no],
                      selectedValue: isGen1a ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!
                            .setMf1Gen1aMode(index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  Text(localizations.mode_gen2),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: [localizations.yes, localizations.no],
                      selectedValue: isGen2 ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!
                            .setMf1Gen2Mode(index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  Text(localizations.use_from_block),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: [localizations.yes, localizations.no],
                      selectedValue: isAntiColl ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!
                            .setMf1UseFirstBlockColl(index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  Text(localizations.collect_nonces("Mfkey32")),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: [localizations.yes, localizations.no],
                      selectedValue: isDetection ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!.setMf1DetectionStatus(
                            isDetection = index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  ...(isDetection)
                      ? [
                          ...(detectionCount == 0)
                              ? [
                                  const SizedBox(height: 8),
                                  Text(localizations.present_cham_reader_keys,
                                      textScaleFactor: 0.8)
                                ]
                              : [
                                  const SizedBox(height: 8),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              appState.forceMfkey32Page = true;
                                              appState.changesMade();
                                            },
                                            child: Row(
                                              children: [
                                                const Icon(Icons.lock_open),
                                                Text(
                                                    localizations.recover_keys),
                                              ],
                                            )),
                                      ]),
                                ],
                        ]
                      : [
                          const SizedBox(height: 8),
                          Text(localizations.ena_coll_recover_keys,
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
                      selectedValue: writeMode.value,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);

                        if (index == 0) {
                          await appState.communicator!
                              .setMf1WriteMode(MifareClassicWriteMode.normal);
                        } else if (index == 1) {
                          await appState.communicator!
                              .setMf1WriteMode(MifareClassicWriteMode.denied);
                        } else if (index == 2) {
                          await appState.communicator!
                              .setMf1WriteMode(MifareClassicWriteMode.deceive);
                        } else if (index == 3) {
                          await appState.communicator!
                              .setMf1WriteMode(MifareClassicWriteMode.shadow);
                        }

                        widget.refresh(widget.slot);
                      }),
                ])));
          }
        });
  }
}
