import 'dart:typed_data';

import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/export.dart';
import 'package:chameleonultragui/gui/menu/pages/dump_editor.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/slot_dump.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/menu/dialogs/confirm_delete.dart';

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

  Future<void> openHfDumpEditor() async {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    var navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(localizations.please_wait)),
          ],
        ),
      ),
    );

    CardSave card;
    try {
      await appState.communicator!.activateSlot(widget.slot);
      card = await readHfDumpFromSlot(
          appState.communicator!, names.hf, slotTypes.hf);
    } catch (e) {
      appState.log!.e("Failed to read slot dump: $e");
      navigator.pop();
      return;
    }

    navigator.pop();

    if (!mounted) {
      return;
    }

    List<Uint8List>? editedDump;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => DumpEditor(
          cardSave: card,
          onSave: (dumpData) {
            editedDump = dumpData;
          },
        ),
      ),
    );

    if (editedDump == null || !mounted) {
      return;
    }

    ValueNotifier<double> progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(localizations.uploading_dump),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) =>
                  LinearProgressIndicator(value: value),
            ),
          ],
        ),
      ),
    );

    try {
      await writeHfDumpToSlot(
          appState.communicator!, widget.slot, slotTypes.hf, editedDump!,
          onProgress: (p) => progress.value = p / 100);
    } catch (e) {
      appState.log!.e("Failed to write slot dump: $e");
    } finally {
      navigator.pop();
      progress.dispose();
    }
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${localizations.hf}:'),
                          const Spacer(),
                          IconButton(
                            onPressed: () async {
                              showDialog<String>(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      SlotEditMenu(
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
                            onPressed: (isMifareClassic(slotTypes.hf) ||
                                    isMifareUltralight(slotTypes.hf))
                                ? openHfDumpEditor
                                : null,
                            icon: const Icon(Icons.edit_document),
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
                          Switch(
                            value: enabledSlot.hf,
                            onChanged: (bool value) async {
                              await appState.communicator!.enableSlot(
                                  widget.slot, TagFrequency.hf, value);

                              setState(() {
                                enabledSlot.hf = value;
                              });

                              widget.refresh();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: null,
                          child: Text(
                            names.hf,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${localizations.lf}:'),
                          const Spacer(),
                          IconButton(
                            onPressed: () async {
                              showDialog<String>(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      SlotEditMenu(
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
                          Switch(
                            value: enabledSlot.lf,
                            onChanged: (bool value) async {
                              await appState.communicator!.enableSlot(
                                  widget.slot, TagFrequency.lf, value);

                              setState(() {
                                enabledSlot.lf = value;
                              });

                              widget.refresh();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: null,
                          child: Text(
                            names.lf,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ])));
          }
        });
  }
}
