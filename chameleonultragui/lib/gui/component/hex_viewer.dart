import 'dart:typed_data';

import 'package:flutter/material.dart';

class HexViewer extends StatefulWidget {
  final Uint8List data;
  final int bytesPerRow;
  final bool scrollVertically;
  final TextStyle? style;
  final Color? addressColor;
  final Color? dividerColor;
  final Color? Function(int value)? byteColorBuilder;
  final Color? Function(int offset, int value)? indexedByteColorBuilder;
  final String Function(Uint8List row)? trailingTextBuilder;

  const HexViewer({
    super.key,
    required this.data,
    this.bytesPerRow = 16,
    this.scrollVertically = true,
    this.style,
    this.addressColor,
    this.dividerColor,
    this.byteColorBuilder,
    this.indexedByteColorBuilder,
    this.trailingTextBuilder,
  });

  @override
  State<HexViewer> createState() => _HexViewerState();
}

class _HexViewerState extends State<HexViewer> {
  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
    _horizontalController = ScrollController();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ??
        Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontFamily: 'RobotoMono',
            );
    final resolvedAddressColor =
        widget.addressColor ?? Theme.of(context).colorScheme.secondary;
    final resolvedDividerColor = widget.dividerColor ??
        Theme.of(context).dividerColor.withValues(alpha: 0.65);
    final spans = <InlineSpan>[];

    for (int offset = 0;
        offset < widget.data.length;
        offset += widget.bytesPerRow) {
      final row = widget.data.sublist(
        offset,
        (offset + widget.bytesPerRow).clamp(0, widget.data.length),
      );

      spans.add(
        TextSpan(
          text: '${offset.toRadixString(16).padLeft(4, '0')}  ',
          style: textStyle.copyWith(color: resolvedAddressColor),
        ),
      );

      for (int index = 0; index < row.length; index++) {
        final byte = row[index];
        final absoluteOffset = offset + index;
        spans.add(
          TextSpan(
            text: byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
            style: textStyle.copyWith(
              color:
                  widget.indexedByteColorBuilder?.call(absoluteOffset, byte) ??
                      widget.byteColorBuilder?.call(byte),
            ),
          ),
        );
        if (index != row.length - 1) {
          spans.add(TextSpan(text: ' ', style: textStyle));
        }
      }

      final trailing = widget.trailingTextBuilder?.call(row);
      if (trailing != null && trailing.isNotEmpty) {
        spans.add(
          TextSpan(
            text: '  ',
            style: textStyle.copyWith(color: resolvedDividerColor),
          ),
        );
        spans.add(
          TextSpan(
            text: trailing,
            style: textStyle.copyWith(color: resolvedDividerColor),
          ),
        );
      }

      if (offset + widget.bytesPerRow < widget.data.length) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    final text = SelectableText.rich(
      TextSpan(style: textStyle, children: spans),
    );

    final horizontalContent = RawScrollbar(
      controller: _horizontalController,
      thumbVisibility: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        primary: false,
        scrollDirection: Axis.horizontal,
        child: text,
      ),
    );

    if (!widget.scrollVertically) {
      return horizontalContent;
    }

    return RawScrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _verticalController,
        primary: false,
        child: horizontalContent,
      ),
    );
  }
}
