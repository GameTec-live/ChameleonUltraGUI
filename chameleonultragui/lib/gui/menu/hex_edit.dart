import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
//import 'package:provider/provider.dart';
//import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class HexEditMenu extends StatefulWidget {
  final CardSave tagSave;

  const HexEditMenu({Key? key, required this.tagSave})
      : super(key: key);

  @override
  HexEditMenuState createState() => HexEditMenuState();
}

class HexEditMenuState extends State<HexEditMenu> {
  @override
  void initState() {
    super.initState();
  }

  final List<TextEditingController> _controllers = [];

  List<Widget> cardSaveToBlockView(CardSave card) {
    List<Widget> sectors = [];
    List<String> blocks = [];
    List<Uint8List> data = card.data;

    // one block consists of 16 bytes
    // Split the data into blocks
    // 4 blocks per sector
    for (var i = 0; i < data.length; i += 4) {
      try {
        if (data[i].isEmpty) {
          blocks.add("");
        } else {
          blocks.add("${bytesToHexSpace(data[i])}\n${bytesToHexSpace(data[i + 1])}\n${bytesToHexSpace(data[i + 2])}\n${bytesToHexSpace(data[i + 3])}");
        }
      } on RangeError {
        // If the data is not divisible by 4, add the remaining byte(s)
        blocks.add(bytesToHexSpace(data[i]));
      }

      // Create a new TextEditingController for each sector
      _controllers.add(TextEditingController(text: blocks.last));
    }

    for (var i = 0; i < blocks.length; i++) {
      sectors.add(const SizedBox(height: 10));
      sectors.add(
        TextField(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Sector $i',
          ),
          controller: _controllers[i],
          keyboardType: TextInputType.multiline,
          maxLines: null,
          onChanged: (value) async {},
        ),
      );
    }

    return sectors;
  }

  List<Uint8List> extractDataFromTextFields() {
    List<Uint8List> data = [];

    for (var i = 0; i < _controllers.length; i++) {
      String text = _controllers[i].text;
      List<String> lines = text.split('\n');
      for (var line in lines) {
        data.add(hexToBytesSpace(line.toUpperCase()));
      }
    }

    return data;
  }

  @override
  Widget build(BuildContext context) {
    //var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.edit_hex),
      content: SingleChildScrollView(
        child: Column(
          children: [
            ...cardSaveToBlockView(widget.tagSave),
          ],
        )
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () {
            List<Uint8List> data = extractDataFromTextFields();
            widget.tagSave.data = data;

            // Return data back to widget that called this dialog
            Navigator.pop(context, data);
          },
          child: Text(localizations.save),
        ),
      ],
    );
  }
}
