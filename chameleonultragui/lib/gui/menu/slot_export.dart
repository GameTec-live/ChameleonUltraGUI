import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SlotExportMenu extends StatefulWidget {
  final List<String> names;
  final List<(bool, bool)> enabledSlots;
  final List<(TagType, TagType)> usedSlots;
  final int slot;

  const SlotExportMenu(
      {Key? key,
      required this.names,
      required this.enabledSlots,
      required this.usedSlots,
      required this.slot})
      : super(key: key);

  @override
  SlotExportMenuState createState() => SlotExportMenuState();
}

class SlotExportMenuState extends State<SlotExportMenu> {
  TagFrequency exportFrequency = TagFrequency.hf;

  Future<CardSave> rebuildCardSaveFromSlot(
      TagFrequency frequency, int slot) async {
    var appState = context.read<ChameleonGUIState>();

    if (frequency == TagFrequency.lf) {
      return CardSave(
        uid:
            bytesToHexSpace(await appState.communicator!.getEM410XEmulatorID()),
        name: widget.names[1],
        tag: widget.usedSlots[slot].$2,
      );
    } else {
      CardData data = await appState.communicator!.mf1GetAntiCollData();
      List<Uint8List> binData = [];

      int blockCount = mfClassicGetBlockCount(
          chameleonTagTypeGetMfClassicType(widget.usedSlots[slot].$1));
      for (int block = 0; block < blockCount; block += 16) {
        Uint8List blockData =
            await appState.communicator!.mf1GetEmulatorBlock(block, block + 16);
        binData.add(blockData);
      }

      return CardSave(
        uid: bytesToHexSpace(data.uid),
        name: widget.names[0],
        sak: data.sak,
        atqa: data.atqa,
        ats: data.ats,
        tag: widget.usedSlots[slot].$1,
        data: binData,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();

    List<String> buttons = [];
    if (widget.usedSlots[widget.slot].$1 != TagType.unknown) {
      buttons.add(localizations.hf);
    }

    if (widget.usedSlots[widget.slot].$2 != TagType.unknown) {
      buttons.add(localizations.lf);
    }

    setState(() {
      exportFrequency =
          buttons[0] == localizations.hf ? TagFrequency.hf : TagFrequency.lf;
    });

    return AlertDialog(
      title: Text(localizations.export_slot_data),
      content: SingleChildScrollView(
          child: Column(
        children: [
          Text(localizations.frequency_to_export),
          const SizedBox(height: 8),
          ToggleButtonsWrapper(
              items: buttons,
              selectedValue: 0,
              onChange: (int index) async {
                setState(() {
                  exportFrequency = buttons[index] == localizations.hf
                      ? TagFrequency.hf
                      : TagFrequency.lf;
                });
              }),
        ],
      )),
      actions: [
        ElevatedButton(
          onPressed: () async {
            CardSave cardSave =
                await rebuildCardSaveFromSlot(exportFrequency, widget.slot);
            Uint8List export = const Utf8Encoder().convert(cardSave.toJson());
            try {
              await FileSaver.instance.saveAs(
                  name: '${cardSave.name}.json',
                  bytes: export,
                  ext: 'json',
                  mimeType: MimeType.json);
            } on UnimplementedError catch (_) {
              String? outputFile = await FilePicker.platform.saveFile(
                dialogTitle: '${localizations.output_file}:',
                fileName: '${cardSave.name}.json',
              );

              if (outputFile != null) {
                var file = File(outputFile);
                await file.writeAsBytes(export);
              }
            }
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(localizations.save_to_file),
        ),
        ElevatedButton(
          onPressed: () async {
            var tags = appState.sharedPreferencesProvider.getCards();
            tags.add(
                await rebuildCardSaveFromSlot(exportFrequency, widget.slot));
            appState.sharedPreferencesProvider.setCards(tags);
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(localizations.export_to_new_card),
        ),
        ElevatedButton(
          onPressed: () async {},
          child: Text(localizations.update_saved_card),
        ),
      ],
    );
  }
}
