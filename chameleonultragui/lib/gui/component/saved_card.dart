import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SavedCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String firstLine;
  final String secondLine;
  final List<Widget> children;
  final int itemIndex;
  final VoidCallback? onPressed;

  const SavedCard(
      {super.key,
      required this.icon,
      required this.iconColor,
      required this.firstLine,
      required this.secondLine,
      required this.children,
      required this.itemIndex,
      required this.onPressed});

  @override
  SavedCardState createState() => SavedCardState();
}

class SavedCardState extends State<SavedCard> {
  @override
  void initState() {
    super.initState();
  }

  // good luck understanding it
  // some values went from Flutter Inspector, some logically calculated
  bool shouldMoveIcons() {
    var appState = context.read<ChameleonGUIState>();

    double readWidth = MediaQuery.of(context).size.width;
    double predictedElementWidth = readWidth >= 700
        ? (readWidth - appState.navigationRailSize!.width - 38) / 2
        : (readWidth - appState.navigationRailSize!.width - 28);
    double iconsWidth = widget.children.length * 40 + 8; // 8 - padding
    double textWidth = (TextPainter(
            text: TextSpan(text: widget.secondLine),
            maxLines: 1,
            textScaler: MediaQuery.of(context).textScaler,
            textDirection: TextDirection.ltr)
          ..layout())
        .size
        .width;
    double textEndsAt = textWidth + 85; // icon + padding

    return textEndsAt + iconsWidth > predictedElementWidth;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();

    return Container(
        constraints: BoxConstraints(maxHeight: !shouldMoveIcons() ? 90 : 130),
        child: ElevatedButton(
            onPressed: widget.onPressed,
            style: customCardButtonStyle(appState),
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 8.0, bottom: 6.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Expanded(
                        child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Row(
                              children: [
                                Transform(
                                  transform:
                                      Matrix4.translationValues(-5, 18, 0),
                                  child: Icon(widget.icon,
                                      color: widget.iconColor),
                                ),
                                const SizedBox(width: 5),
                                FittedBox(
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    widget.firstLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )))
                  ]),
                  if (shouldMoveIcons()) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            const SizedBox(width: 30),
                            FittedBox(
                                alignment: Alignment.centerLeft,
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  widget.secondLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ))
                          ],
                        ),
                      )),
                      if (!shouldMoveIcons()) ...widget.children
                    ],
                  ),
                  ...(shouldMoveIcons())
                      ? [
                          const SizedBox(height: 10),
                          FittedBox(
                              alignment: Alignment.centerRight,
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: widget.children,
                              ))
                        ]
                      : []
                ],
              ),
            )));
  }
}
