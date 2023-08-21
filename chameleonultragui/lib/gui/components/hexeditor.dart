import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'dart:typed_data';
class HexEdit extends StatefulWidget {
  final List<Uint8List> data;

  const HexEdit({Key? key, required this.data}) : super(key: key);

  @override
  HexEditState createState() => HexEditState();
}

class HexEditState extends State<HexEdit> {

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {

    List<TextField> sectors = [];

    for (var i = 0, x = 0; i < widget.data.length; i += 4, x++) {
      if (widget.data[i].isNotEmpty) {

        String data = '';
        for (var j = 0; j < 4; j++) {
          data += '\n ${bytesToHex(widget.data[i+j])}';
        }

        sectors.add(
          TextField(
            maxLines: null,
            controller: TextEditingController(text: data.toUpperCase()),
            decoration: InputDecoration(
              labelText: 'Sector $x', 
              hintText: 'Enter data'
            ),
          ),
        );
      }
    }

    return AlertDialog(
      title: const Text('Edit Data'),
      content: SizedBox(
        width:  MediaQuery.of(context).size.width / 4,
        height: MediaQuery.of(context).size.height,
        child: ListView(
          children: sectors,
        ),
      ),
      actions: [],
    );
  }
}