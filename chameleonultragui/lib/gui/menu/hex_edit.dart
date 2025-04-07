import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/services.dart';

class HexEditMenu extends StatefulWidget {
  final CardSave tagSave;

  const HexEditMenu({super.key, required this.tagSave});

  @override
  HexEditMenuState createState() => HexEditMenuState();
}

class HexEditMenuState extends State<HexEditMenu> {
  TextEditingController textController = TextEditingController();
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    List<Uint8List> data = widget.tagSave.data;
    String displayText = "";

    // Diplay data. Every 16 bytes in a row
    for (Uint8List sector in data) {
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
    textController.selection =
        TextSelection(baseOffset: currentIndex, extentOffset: currentIndex + 1);
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
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              // Handle enter key event
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              setState(() {
                if (currentIndex < textController.text.length - 1) {
                  currentIndex += 48;
                  if (textController.text[currentIndex] == "\n" ||
                      textController.text[currentIndex] == " ") {
                    currentIndex++;
                  }
                  if (currentIndex > textController.text.length - 1) {
                    currentIndex = textController.text.length - 1;
                  }
                }
                textController.selection = TextSelection(
                    baseOffset: currentIndex, extentOffset: currentIndex + 1);
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              setState(() {
                if (currentIndex > 0) {
                  currentIndex -= 48;
                  if (textController.text[currentIndex] == "\n" ||
                      textController.text[currentIndex] == " ") {
                    currentIndex--;
                  }
                  if (currentIndex < 0) {
                    currentIndex = 0;
                  }
                }
                textController.selection = TextSelection(
                    baseOffset: currentIndex, extentOffset: currentIndex + 1);
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              setState(() {
                if (currentIndex > 0) {
                  if (textController.text[currentIndex] == "\n" ||
                      textController.text[currentIndex] == " ") {
                    currentIndex--;
                  }
                  currentIndex--;
                }
                textController.selection = TextSelection(
                    baseOffset: currentIndex, extentOffset: currentIndex + 1);
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              setState(() {
                if (currentIndex < textController.text.length - 1) {
                  currentIndex++;
                  if (textController.text[currentIndex] == "\n" ||
                      textController.text[currentIndex] == " ") {
                    currentIndex++;
                  }
                }
                textController.selection = TextSelection(
                    baseOffset: currentIndex, extentOffset: currentIndex + 1);
              });
              return KeyEventResult.handled;
            }
            print("Key pressed: ${event.logicalKey}");
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            TextField(
              autofocus: true,
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
