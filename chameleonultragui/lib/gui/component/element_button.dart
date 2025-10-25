import 'dart:math';

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
  static const double _iconSize = 32.0;
  static const double _iconSpacing = 8.0;
  static const double _iconTransformX = -5.0;

  @override
  void initState() {
    super.initState();
  }

  double _getIconButtonWidth(BuildContext context) {
    final MaterialTapTargetSize tapTargetSize =
        Theme.of(context).materialTapTargetSize;

    return tapTargetSize == MaterialTapTargetSize.padded ? 48.0 : 40.0;
  }

  bool _shouldMoveIcons(BuildContext context, double availableWidth) {
    if (widget.children.isEmpty) return false;

    double iconButtonWidth = _getIconButtonWidth(context);
    double iconsWidth = widget.children.length * iconButtonWidth + 8;

    TextStyle textStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    TextPainter firstLinePainter = TextPainter(
      text: TextSpan(text: widget.firstLine, style: textStyle),
      maxLines: 1,
      textScaler: MediaQuery.of(context).textScaler,
      textDirection: TextDirection.ltr,
    )..layout();

    TextPainter secondLinePainter = TextPainter(
      text: TextSpan(text: widget.secondLine, style: textStyle),
      maxLines: 1,
      textScaler: MediaQuery.of(context).textScaler,
      textDirection: TextDirection.ltr,
    )..layout();

    double textWidth =
        max(firstLinePainter.size.width, secondLinePainter.size.width);

    double horizontalSpacing = _iconSize + _iconSpacing + _iconTransformX;

    double contentWidthNeeded = horizontalSpacing + textWidth;
    double totalWidthNeeded = contentWidthNeeded + iconsWidth;

    return totalWidthNeeded > availableWidth;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();

    return ElevatedButton(
        onPressed: widget.onPressed,
        style: customCardButtonStyle(appState),
        child: Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 8.0, bottom: 6.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              bool moveIcons = _shouldMoveIcons(context, constraints.maxWidth);

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: !moveIcons ? 90 : 130),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Transform(
                          transform:
                              Matrix4.translationValues(_iconTransformX, 0, 0),
                          child: Icon(
                            widget.icon,
                            color: widget.iconColor,
                            size: _iconSize,
                          ),
                        ),
                        const SizedBox(width: _iconSpacing),
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
                        if (!moveIcons) ...widget.children
                      ],
                    ),
                    if (moveIcons) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: widget.children,
                      ),
                    ]
                  ],
                ),
              );
            },
          ),
        ));
  }
}
