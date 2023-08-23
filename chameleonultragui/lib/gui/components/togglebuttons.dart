import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ToggleButtonsWrapper extends StatefulWidget {
  List<String> items;
  int selectedValue;
  dynamic onChange;

  ToggleButtonsWrapper(
      {Key? key,
      required this.items,
      required this.selectedValue,
      required this.onChange})
      : super(key: key);

  @override
  ToggleButtonsState createState() => ToggleButtonsState();
}

class ToggleButtonsState extends State<ToggleButtonsWrapper> {
  List<Widget> textItems = [];
  List<bool> values = [];

  @override
  void initState() {
    super.initState();
    int count = 0;
    for (var text in widget.items) {
      textItems.add(Text(text));
      values.add(count == widget.selectedValue);
      count++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToggleButtons(
      direction: Axis.horizontal,
      onPressed: (int index) async {
        setState(() {
          for (int i = 0; i < values.length; i++) {
            values[i] = i == index;
          }
        });
        await widget.onChange(index);
      },
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      constraints: const BoxConstraints(
        minHeight: 40.0,
        minWidth: 80.0,
      ),
      isSelected: values,
      children: textItems,
    );
  }
}
