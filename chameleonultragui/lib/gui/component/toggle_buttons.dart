import 'package:flutter/material.dart';

class ToggleButtonsWrapper extends StatefulWidget {
  final List<String> items;
  final int selectedValue;
  final dynamic onChange;

  const ToggleButtonsWrapper(
      {super.key,
      required this.items,
      required this.selectedValue,
      required this.onChange});

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
    return FittedBox(
        alignment: Alignment.centerRight,
        fit: BoxFit.scaleDown,
        child: ToggleButtons(
          direction: Axis.horizontal,
          onPressed: (int index) async {
            setState(() {
              for (int i = 0; i < values.length; i++) {
                values[i] = i == index;
              }
            });
            await widget.onChange(index);
          },
          borderRadius: const BorderRadius.all(Radius.circular(32)),
          constraints: const BoxConstraints(
            minHeight: 40.0,
            minWidth: 80.0,
          ),
          isSelected: values,
          children: textItems,
        ));
  }
}
