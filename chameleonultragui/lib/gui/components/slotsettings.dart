import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/components/togglebuttons.dart';
import 'package:chameleonultragui/helpers/mifare_classic.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

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
  late bool isGen1a;
  late bool isGen2;
  late bool isAntiColl;
  late ChameleonMf1WriteMode writeMode;
  String hfName = "";
  String lfName = "";

  @override
  void initState() {
    super.initState();
  }

  Future<void> fetchInfo() async {
    var appState = context.read<MyAppState>();

    if (hfName.isEmpty) {
      try {
        hfName = (await appState.communicator!
                .getSlotTagName(widget.slot, ChameleonTagFrequiency.hf))
            .trim();
      } catch (_) {}

      if (hfName.isEmpty) {
        hfName = "Empty";
      }

      setState(() {});
    }

    if (lfName.isEmpty) {
      try {
        lfName = (await appState.communicator!
                .getSlotTagName(widget.slot, ChameleonTagFrequiency.lf))
            .trim();
      } catch (_) {}

      if (lfName.isEmpty) {
        lfName = "Empty";
      }

      setState(() {});
    }

    if (!isRun) {
      await appState.communicator!.activateSlot(widget.slot);
      isEnabled = (await appState.communicator!.getEnabledSlots())[widget.slot];
      var data = (await appState.communicator!.getMf1EmulatorConfig());
      isDetection = data.$1;
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
    var appState = context.watch<MyAppState>();

    return FutureBuilder(
        future: fetchInfo(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !isRun) {
            return const AlertDialog(
                title: Text('Slot settings'),
                content: SingleChildScrollView(
                    child: Column(children: [CircularProgressIndicator()])));
          } else if (snapshot.hasError) {
            appState.connector.preformDisconnect();
            return Text('Error: ${snapshot.error.toString()}');
          } else {
            return AlertDialog(
                title: const Text('Slot settings'),
                content: SingleChildScrollView(
                    child: Column(children: [
                  Row(
                    children: [
                      const Text('HF:'),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton(
                        onPressed: null,
                        child: Text(hfName),
                      )),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          await appState.communicator!.deleteSlotInfo(
                              widget.slot, ChameleonTagFrequiency.hf);
                          await appState.communicator!.setSlotTagName(
                              widget.slot, "Empty", ChameleonTagFrequiency.hf);
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
                      const Text('LF:'),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton(
                        onPressed: null,
                        child: Text(lfName),
                      )),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          await appState.communicator!.deleteSlotInfo(
                              widget.slot, ChameleonTagFrequiency.lf);
                          await appState.communicator!.setSlotTagName(
                              widget.slot, "Empty", ChameleonTagFrequiency.lf);
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
                  const Text(
                    'Mifare Classic emulator settings',
                    textScaleFactor: 1.2,
                  ),
                  const SizedBox(height: 8),
                  const Text('Gen1A magic mode'),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: const ['Yes', 'No'],
                      selectedValue: isGen1a ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!
                            .setMf1Gen1aMode(index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  const Text('Gen2 magic mode'),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: const ['Yes', 'No'],
                      selectedValue: isGen2 ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!
                            .setMf1Gen2Mode(index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  const Text('Use UID/SAK/ATQA from 0 block'),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: const ['Yes', 'No'],
                      selectedValue: isAntiColl ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!
                            .setMf1UseFirstBlockColl(index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  const Text('Collect nonces (Mfkey32)'),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: const ['Yes', 'No'],
                      selectedValue: isDetection ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);
                        await appState.communicator!
                            .setMf1DetectionStatus(index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  const Text('Write mode'),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: const ['Normal', 'Decline', 'Deceive', 'Shadow'],
                      selectedValue: writeMode.value,
                      onChange: (int index) async {
                        await appState.communicator!.activateSlot(widget.slot);

                        if (index == 0) {
                          await appState.communicator!
                              .setMf1WriteMode(ChameleonMf1WriteMode.normal);
                        } else if (index == 1) {
                          await appState.communicator!
                              .setMf1WriteMode(ChameleonMf1WriteMode.deined);
                        } else if (index == 2) {
                          await appState.communicator!
                              .setMf1WriteMode(ChameleonMf1WriteMode.deceive);
                        } else if (index == 3) {
                          await appState.communicator!
                              .setMf1WriteMode(ChameleonMf1WriteMode.shadow);
                        }

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 32),
                  const Text('Slot status'),
                  const SizedBox(height: 8),
                  ToggleButtonsWrapper(
                      items: const ['Enabled', 'Disabled'],
                      selectedValue: isEnabled ? 0 : 1,
                      onChange: (int index) async {
                        await appState.communicator!
                            .enableSlot(widget.slot, index == 0 ? true : false);

                        widget.refresh(widget.slot);
                      }),
                  const SizedBox(height: 8),
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () {
                      widget.refresh(widget.slot);
                      Navigator.pop(context);
                    },
                  ),
                ])));
          }
        });
  }
}
