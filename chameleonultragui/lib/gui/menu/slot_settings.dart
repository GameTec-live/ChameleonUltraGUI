import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/slot_edit.dart';
import 'package:chameleonultragui/gui/menu/slot_export.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/menu/confirm_delete.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

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
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    await appState.communicator!.activateSlot(widget.slot);

    try {
      String name = (await appState.communicator!
              .getSlotTagName(widget.slot, TagFrequency.hf))
          .trim();
      if (name.isEmpty) {
        names.hf = localizations.empty;
      } else {
        names.hf = name;
      }
    } catch (_) {}

    try {
      String name = (await appState.communicator!
              .getSlotTagName(widget.slot, TagFrequency.lf))
          .trim();
      if (name.isEmpty) {
        names.lf = localizations.empty;
      } else {
        names.lf = name;
      }
    } catch (_) {}

    enabledSlot = (await appState.communicator!.getEnabledSlots())[widget.slot];
    slotTypes = (await appState.communicator!.getSlotTagTypes())[widget.slot];

    setState(() {});
  }

  void updateSlot(String name, TagFrequency frequency, TagType type) {
    if (frequency == TagFrequency.hf) {
      names.hf = name;
      slotTypes.hf = type;
    } else if (frequency == TagFrequency.lf) {
      names.lf = name;
      slotTypes.lf = type;
    }

    widget.refresh();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return FutureBuilder(
        future: (names.hf.isNotEmpty) ? Future.value(null) : fetchInfo(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              names.hf.isEmpty) {
            return AlertDialog(
                title: Text(localizations.slot_settings),
                content: const SingleChildScrollView(
                    child: Column(children: [CircularProgressIndicator()])));
          } else if (snapshot.hasError) {
            appState.connector!.performDisconnect();
            return AlertDialog(
                title: Text(localizations.slot_settings),
                content: ErrorPage(errorMessage: snapshot.error.toString()));
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
                        onPressed: null,
                        child: Text(names.hf),
                      )),
                      const SizedBox(width: 8),
                      Switch(
                        value: enabledSlot.hf,
                        onChanged: (bool value) async {
                          await appState.communicator!
                              .enableSlot(widget.slot, TagFrequency.hf, value);

                          setState(() {
                            enabledSlot.hf = value;
                          });

                          widget.refresh();
                        },
                      ),
                      IconButton(
                        onPressed: () async {
                          showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => SlotEditMenu(
                                  name: names.hf,
                                  isEnabled: enabledSlot.hf,
                                  slotType: slotTypes.hf,
                                  frequency: TagFrequency.hf,
                                  slot: widget.slot,
                                  update: updateSlot));
                        },
                        icon: const Icon(Icons.edit),
                      ),
                      IconButton(
                        onPressed: () async {
                          if (appState.sharedPreferencesProvider
                                  .getConfirmDelete() ==
                              true) {
                            var confirm = await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return ConfirmDeletionMenu(
                                    thingBeingDeleted: names.hf);
                              },
                            );

                            if (confirm != true) {
                              return;
                            }
                          }
                          await appState.communicator!
                              .deleteSlotInfo(widget.slot, TagFrequency.hf);
                          await appState.communicator!.setSlotTagName(
                              widget.slot,
                              localizations.empty,
                              TagFrequency.hf);
                          await appState.communicator!.saveSlotData();

                          setState(() {
                            names.hf = localizations.empty;
                            slotTypes.hf = TagType.unknown;
                          });

                          widget.refresh();
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
                        child: Text(names.lf),
                      )),
                      const SizedBox(width: 8),
                      Switch(
                        value: enabledSlot.lf,
                        onChanged: (bool value) async {
                          await appState.communicator!
                              .enableSlot(widget.slot, TagFrequency.lf, value);

                          setState(() {
                            enabledSlot.lf = value;
                          });

                          widget.refresh();
                        },
                      ),
                      IconButton(
                        onPressed: () async {
                          showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => SlotEditMenu(
                                  name: names.lf,
                                  isEnabled: enabledSlot.lf,
                                  slotType: slotTypes.lf,
                                  frequency: TagFrequency.lf,
                                  slot: widget.slot,
                                  update: updateSlot));
                        },
                        icon: const Icon(Icons.edit),
                      ),
                      IconButton(
                        onPressed: () async {
                          if (appState.sharedPreferencesProvider
                                  .getConfirmDelete() ==
                              true) {
                            var confirm = await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return ConfirmDeletionMenu(
                                    thingBeingDeleted: names.lf);
                              },
                            );

                            if (confirm != true) {
                              return;
                            }
                          }
                          await appState.communicator!
                              .deleteSlotInfo(widget.slot, TagFrequency.lf);
                          await appState.communicator!.setSlotTagName(
                              widget.slot,
                              localizations.empty,
                              TagFrequency.lf);
                          await appState.communicator!.saveSlotData();

                          setState(() {
                            names.lf = localizations.empty;
                            slotTypes.lf = TagType.unknown;
                          });

                          widget.refresh();
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                    ],
                  ),
                ])));
          }
        });
  }
}
