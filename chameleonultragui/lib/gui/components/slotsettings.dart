import 'package:chameleonultragui/bridge/chameleon.dart';
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
  List<bool> selectedGen1aMode = <bool>[true, false];
  List<bool> selectedGen2Mode = <bool>[true, false];
  List<bool> selectedAntiColl = <bool>[true, false];
  List<bool> selectedDetection = <bool>[true, false];
  List<bool> selectedWriteMode = <bool>[false, false, false, false];
  List<bool> selectedEnabled = <bool>[true, false];
  bool firstRun = true;
  String hfName = "";
  String lfName = "";

  @override
  void initState() {
    super.initState();
  }

  Future<void> fetchInfo() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);

    if (hfName.isEmpty) {
      try {
        hfName = (await connection.getSlotTagName(
                widget.slot, ChameleonTagFrequiency.hf))
            .trim();
      } catch (_) {}

      if (hfName.isEmpty) {
        hfName = "Empty";
      }

      setState(() {});
    }

    if (lfName.isEmpty) {
      try {
        lfName = (await connection.getSlotTagName(
                widget.slot, ChameleonTagFrequiency.lf))
            .trim();
      } catch (_) {}

      if (lfName.isEmpty) {
        lfName = "Empty";
      }

      setState(() {});
    }

    if (firstRun) {
      firstRun = false;
      await connection.activateSlot(widget.slot);
      bool isEnabled = (await connection.getEnabledSlots())[widget.slot];
      if (!isEnabled) {
        selectedEnabled = selectedEnabled.reversed.toList();
      }
      var (isDetection, isGen1a, isGen2, isAntiColl, writeMode) =
          (await connection.getMf1EmulatorConfig());
      if (!isDetection) {
        selectedDetection = selectedDetection.reversed.toList();
      }
      if (!isGen1a) {
        selectedGen1aMode = selectedGen1aMode.reversed.toList();
      }
      if (!isGen2) {
        selectedGen2Mode = selectedGen2Mode.reversed.toList();
      }
      if (!isAntiColl) {
        selectedAntiColl = selectedAntiColl.reversed.toList();
      }

      if (writeMode == ChameleonMf1WriteMode.normal) {
        selectedWriteMode[0] = true;
      } else if (writeMode == ChameleonMf1WriteMode.deined) {
        selectedWriteMode[1] = true;
      } else if (writeMode == ChameleonMf1WriteMode.deceive) {
        selectedWriteMode[2] = true;
      } else if (writeMode == ChameleonMf1WriteMode.shadow) {
        selectedWriteMode[3] = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);

    return FutureBuilder(
        future: fetchInfo(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
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
                      onPressed: () {},
                      child: Text(hfName),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        await connection.deleteSlotInfo(
                            widget.slot, ChameleonTagFrequiency.hf);
                        await connection.setSlotTagName(
                            widget.slot, "Empty", ChameleonTagFrequiency.hf);
                        await connection.saveSlotData();

                        setState(() {
                          hfName = "";
                        });

                        widget.refresh();
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ],
                ),
                const Text(
                  'Mifare Classic emulator settings',
                  textScaleFactor: 1.2,
                ),
                const SizedBox(height: 8),
                const Text('Gen1A magic mode'),
                const SizedBox(height: 8),
                ToggleButtons(
                  direction: Axis.horizontal,
                  onPressed: (int index) async {
                    setState(() {
                      for (int i = 0; i < selectedGen1aMode.length; i++) {
                        selectedGen1aMode[i] = i == index;
                      }
                    });
                    await connection.activateSlot(widget.slot);
                    await connection.setMf1Gen1aMode(index == 0 ? true : false);

                    widget.refresh();
                  },
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    minWidth: 80.0,
                  ),
                  isSelected: selectedGen1aMode,
                  children: const <Widget>[Text('Yes'), Text('No')],
                ),
                const SizedBox(height: 8),
                const Text('Gen2 magic mode'),
                const SizedBox(height: 8),
                ToggleButtons(
                  direction: Axis.horizontal,
                  onPressed: (int index) async {
                    setState(() {
                      for (int i = 0; i < selectedGen2Mode.length; i++) {
                        selectedGen2Mode[i] = i == index;
                      }
                    });

                    await connection.activateSlot(widget.slot);
                    await connection.setMf1Gen2Mode(index == 0 ? true : false);

                    widget.refresh();
                  },
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    minWidth: 80.0,
                  ),
                  isSelected: selectedGen2Mode,
                  children: const <Widget>[Text('Yes'), Text('No')],
                ),
                const SizedBox(height: 8),
                const Text('Use UID/SAK/ATQA from 0 block'),
                const SizedBox(height: 8),
                ToggleButtons(
                  direction: Axis.horizontal,
                  onPressed: (int index) async {
                    setState(() {
                      for (int i = 0; i < selectedAntiColl.length; i++) {
                        selectedAntiColl[i] = i == index;
                      }
                    });

                    await connection.activateSlot(widget.slot);
                    await connection
                        .setMf1UseFirstBlockColl(index == 0 ? true : false);

                    widget.refresh();
                  },
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    minWidth: 80.0,
                  ),
                  isSelected: selectedAntiColl,
                  children: const <Widget>[Text('Yes'), Text('No')],
                ),
                const SizedBox(height: 8),
                const Text('Collect nonces (Mfkey32)'),
                const SizedBox(height: 8),
                ToggleButtons(
                  direction: Axis.horizontal,
                  onPressed: (int index) async {
                    setState(() {
                      for (int i = 0; i < selectedDetection.length; i++) {
                        selectedDetection[i] = i == index;
                      }
                    });

                    await connection.activateSlot(widget.slot);
                    await connection
                        .setMf1DetectionStatus(index == 0 ? true : false);

                    widget.refresh();
                  },
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    minWidth: 80.0,
                  ),
                  isSelected: selectedDetection,
                  children: const <Widget>[Text('Yes'), Text('No')],
                ),
                const SizedBox(height: 8),
                const Text('Write mode'),
                const SizedBox(height: 8),
                ToggleButtons(
                  direction: Axis.horizontal,
                  onPressed: (int index) async {
                    setState(() {
                      for (int i = 0; i < selectedWriteMode.length; i++) {
                        selectedWriteMode[i] = i == index;
                      }
                    });

                    await connection.activateSlot(widget.slot);

                    if (index == 0) {
                      await connection
                          .setMf1WriteMode(ChameleonMf1WriteMode.normal);
                    } else if (index == 1) {
                      await connection
                          .setMf1WriteMode(ChameleonMf1WriteMode.deined);
                    } else if (index == 2) {
                      await connection
                          .setMf1WriteMode(ChameleonMf1WriteMode.deceive);
                    } else if (index == 3) {
                      await connection
                          .setMf1WriteMode(ChameleonMf1WriteMode.shadow);
                    }

                    widget.refresh();
                  },
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    minWidth: 80.0,
                  ),
                  isSelected: selectedWriteMode,
                  children: const <Widget>[
                    Text('Normal'),
                    Text('Decline'),
                    Text('Deceive'),
                    Text('Shadow')
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('LF:'),
                    const SizedBox(width: 8),
                    Expanded(
                        child: OutlinedButton(
                      onPressed: () {},
                      child: Text(lfName),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        await connection.deleteSlotInfo(
                            widget.slot, ChameleonTagFrequiency.lf);
                        await connection.setSlotTagName(
                            widget.slot, "Empty", ChameleonTagFrequiency.lf);
                        await connection.saveSlotData();

                        setState(() {
                          lfName = "";
                        });
                        widget.refresh();
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Slot status'),
                const SizedBox(height: 8),
                ToggleButtons(
                  direction: Axis.horizontal,
                  onPressed: (int index) async {
                    setState(() {
                      for (int i = 0; i < selectedEnabled.length; i++) {
                        selectedEnabled[i] = i == index;
                      }
                    });

                    await connection.enableSlot(
                        widget.slot, index == 0 ? true : false);
                    widget.refresh();
                  },
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  constraints: const BoxConstraints(
                    minHeight: 40.0,
                    minWidth: 80.0,
                  ),
                  isSelected: selectedEnabled,
                  children: const <Widget>[Text('Enabled'), Text('Disabled')],
                ),
                const SizedBox(height: 8),
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    widget.refresh();
                    Navigator.pop(context);
                  },
                ),
              ])));
        });
  }
}
