import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ElementButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String firstLine;
  final String secondLine;
  final List<Widget> children;
  final int itemIndex;
  final VoidCallback? onPressed;
  final int maxLineLines;

  const ElementButton(
      {super.key,
      required this.icon,
      required this.iconColor,
      required this.firstLine,
      required this.secondLine,
      required this.children,
      required this.itemIndex,
      required this.onPressed,
      this.maxLineLines = 1});

  @override
  ElementButtonState createState() => ElementButtonState();
}

class ElementButtonState extends State<ElementButton> {
  @override
  void initState() {
    super.initState();
  }

  bool shouldMoveIcons() {
    var appState = context.read<ChameleonGUIState>();

    double readWidth = MediaQuery.of(context).size.width;
    double predictedElementWidth = readWidth >= 700
        ? (readWidth - appState.navigationRailSize!.width - 38) / 2
        : (readWidth - appState.navigationRailSize!.width - 28);
    double iconsWidth = widget.children.length * 40 + 8;
    double textWidth = (TextPainter(
            text: TextSpan(
                text: widget.secondLine.length > widget.firstLine.length
                    ? widget.secondLine
                    : widget.firstLine),
            maxLines: 1,
            textScaler: MediaQuery.of(context).textScaler,
            textDirection: TextDirection.ltr)
          ..layout())
        .size
        .width;
    double textEndsAt = textWidth + 90;

    return textEndsAt + iconsWidth > predictedElementWidth &&
        widget.children.isNotEmpty;
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Transform(
                        transform: Matrix4.translationValues(-5, 0, 0),
                        child: Icon(
                          widget.icon,
                          color: widget.iconColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.firstLine,
                              maxLines: widget.maxLineLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.secondLine,
                              maxLines: widget.maxLineLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (!shouldMoveIcons()) ...widget.children
                    ],
                  ),
                  if (shouldMoveIcons()) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: widget.children,
                    ),
                  ]
                ],
              ),
            )));
  }
}
