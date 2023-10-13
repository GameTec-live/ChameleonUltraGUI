import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/menu/slot_edit.dart';
import 'package:chameleonultragui/gui/menu/slot_export.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SlotNames {
  String hfName;
  String lfName;

  SlotNames({this.hfName = "", this.lfName = ""});
}

class SlotSettings extends StatefulWidget {
  final int slot;
  final dynamic refresh;

  const SlotSettings({super.key, required this.slot, required this.refresh});

  @override
  SlotSettingsState createState() => SlotSettingsState();
}

class SlotSettingsState extends State<SlotSettings> {
  EnabledSlotInfo enabledSlot = EnabledSlotInfo();
  SlotTypes slotTypes = SlotTypes();
  SlotNames names = SlotNames();
  TagFrequency exportFrequency = TagFrequency.hf;

  @override
  void initState() {
    super.initState();
  }

  Future<void> fetchInfo() async {
    if (names.hfName.isNotEmpty) {
      return;
    }

    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    try {
      String name = (await appState.communicator!
              .getSlotTagName(widget.slot, TagFrequency.hf))
          .trim();
      if (name.isEmpty) {
        names.hfName = localizations.empty;
      } else {
        names.hfName = name;
      }
    } catch (_) {}

    try {
      String name = (await appState.communicator!
              .getSlotTagName(widget.slot, TagFrequency.lf))
          .trim();
      if (name.isEmpty) {
        names.lfName = localizations.empty;
      } else {
        names.lfName = name;
      }
    } catch (_) {}

    enabledSlot = (await appState.communicator!.getEnabledSlots())[widget.slot];
    slotTypes = (await appState.communicator!.getSlotTagTypes())[widget.slot];

    setState(() {});
  }

  void updateSlot(String name, TagFrequency frequency, TagType type) {
    if (frequency == TagFrequency.hf) {
      names.hfName = name;
      slotTypes.hfSlot = type;
    } else if (frequency == TagFrequency.lf) {
      names.lfName = name;
      slotTypes.lfSlot = type;
    }

    widget.refresh(widget.slot);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return FutureBuilder(
        future: fetchInfo(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              names.hfName.isNotEmpty) {
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
                title: Row(
                  children: [
                    Text(localizations.slot_settings),
                    const Spacer(
                      flex: 1,
                    ),
                    IconButton(
                      onPressed: (slotTypes.notMatch())
                          ? () {
                              showDialog<String>(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      SlotExportMenu(
                                          names: names,
                                          enabledSlotInfo: enabledSlot,
                                          slotTypes: slotTypes));
                            }
                          : null,
                      icon: const Icon(Icons.download),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                    child: Column(children: [
                  Row(
                    children: [
                      Text('${localizations.hf}:'),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton(
                        onPressed: () async {
                          showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => SlotEditMenu(
                                  name: names.hfName,
                                  isEnabled: enabledSlot.hfSlot,
                                  slotType: slotTypes.hfSlot,
                                  frequency: TagFrequency.hf,
                                  slot: widget.slot,
                                  update: updateSlot));
                        },
                        child: Text(names.hfName),
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
                            names.hfName = localizations.empty;
                            slotTypes.hfSlot = TagType.unknown;
                          });

                          widget.refresh(widget.slot);
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                      IconButton(
                        onPressed: () async {
                          await appState.communicator!.enableSlot(widget.slot,
                              TagFrequency.hf, !enabledSlot.hfSlot);
                          await appState.communicator!.saveSlotData();

                          setState(() {
                            enabledSlot.hfSlot = !enabledSlot.hfSlot;
                          });

                          widget.refresh(widget.slot);
                        },
                        icon: Icon(enabledSlot.hfSlot
                            ? Icons.toggle_on
                            : Icons.toggle_off),
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
                        onPressed: () async {
                          showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => SlotEditMenu(
                                  name: names.lfName,
                                  isEnabled: enabledSlot.lfSlot,
                                  slotType: slotTypes.lfSlot,
                                  frequency: TagFrequency.lf,
                                  slot: widget.slot,
                                  update: updateSlot));
                        },
                        child: Text(names.lfName),
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
                            names.lfName = localizations.empty;
                            slotTypes.lfSlot = TagType.unknown;
                          });

                          widget.refresh(widget.slot);
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                      IconButton(
                        onPressed: () async {
                          await appState.communicator!.enableSlot(widget.slot,
                              TagFrequency.lf, !enabledSlot.lfSlot);
                          await appState.communicator!.saveSlotData();

                          setState(() {
                            enabledSlot.lfSlot = !enabledSlot.lfSlot;
                          });

                          widget.refresh(widget.slot);
                        },
                        icon: Icon(enabledSlot.lfSlot
                            ? Icons.toggle_on
                            : Icons.toggle_off),
                      ),
                    ],
                  ),
                ])));
          }
        });
  }
}
