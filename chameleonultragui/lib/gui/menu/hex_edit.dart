import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/services.dart';

class HexEditMenu extends StatefulWidget {
  final CardSave tagSave;

  const HexEditMenu({Key? key, required this.tagSave}) : super(key: key);

  @override
  HexEditMenuState createState() => HexEditMenuState();
}

class HexEditMenuState extends State<HexEditMenu> {
  TextEditingController textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    List<Uint8List> data = widget.tagSave.data;
    String displayText = "";

    // Diplay data. Every 16 bytes in a row
    for (Uint8List sector in data) {
      displayText += "\n";
      for (int i = 0; i < sector.length; i += 16) {
        if (i % 64 == 0 && i != 0) {
          displayText += "\n";
        }

        Uint8List block =
            sector.sublist(i, i + 16 > sector.length ? sector.length : i + 16);
        displayText += "${bytesToHexSpace(block)}\n";
      }
    }
    textController.text = displayText;
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  List<Uint8List> extractDataFromTextFields() {
    List<Uint8List> data = [];
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Edit HEX"),
      content: SingleChildScrollView(
          child: FocusScope(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              // Handle enter key event
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            print("Key pressed: ${event.logicalKey}");
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            TextField(
              controller: textController,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              minLines: null,
              style: const TextStyle(fontFamily: "RobotoMono", fontSize: 16),
            ),
          ],
        ),
      )),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            List<Uint8List> data = extractDataFromTextFields();
            widget.tagSave.data = data;

            // Return data back to widget that called this dialog
            Navigator.pop(context, data);
          },
          child: Text("save"),
        ),
      ],
    );
  }
}
