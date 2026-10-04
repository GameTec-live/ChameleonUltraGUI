import 'dart:math';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

class KeyCheckMarks extends StatefulWidget {
  final int checkmarkCount;
  final List<ChameleonKeyCheckmark> checkMarks;
  final List<Uint8List> validKeys;
  final int checkmarkPerRow;
  final double checkmarkSize;
  final double fontSize;
  final void Function(int index, ChameleonKeyCheckmark newValue)?
      onCheckmarkChanged;

  const KeyCheckMarks(
      {super.key,
      required this.checkMarks,
      required this.validKeys,
      this.checkmarkCount = 16,
      this.checkmarkPerRow = 16,
      this.checkmarkSize = 20,
      this.fontSize = 16,
      this.onCheckmarkChanged});

  @override
  State<KeyCheckMarks> createState() => _KeyCheckMarksState();
}

class _KeyCheckMarksState extends State<KeyCheckMarks> {
  final Map<int, GlobalKey> _checkmarkKeys = {};
  final Set<int> _draggedCheckmarks = {};
  ChameleonKeyCheckmark? _dragValue;

  GlobalKey _checkmarkKey(int index) {
    return _checkmarkKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _startCheckmarkDrag(int index) {
    switch (widget.checkMarks[index]) {
      case ChameleonKeyCheckmark.none:
        _dragValue = ChameleonKeyCheckmark.disabled;
        break;
      case ChameleonKeyCheckmark.disabled:
        _dragValue = ChameleonKeyCheckmark.none;
        break;
      case ChameleonKeyCheckmark.found:
      case ChameleonKeyCheckmark.checking:
        _dragValue = null;
        break;
    }

    _draggedCheckmarks.clear();
    _applyDragValue(index);
  }

  void _applyDragValue(int index) {
    final dragValue = _dragValue;
    if (dragValue == null || !_draggedCheckmarks.add(index)) {
      return;
    }

    final currentValue = widget.checkMarks[index];
    if ((currentValue == ChameleonKeyCheckmark.none &&
            dragValue == ChameleonKeyCheckmark.disabled) ||
        (currentValue == ChameleonKeyCheckmark.disabled &&
            dragValue == ChameleonKeyCheckmark.none)) {
      widget.onCheckmarkChanged?.call(index, dragValue);
    }
  }

  void _continueCheckmarkDrag(Offset globalPosition) {
    for (final entry in _checkmarkKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        continue;
      }

      final topLeft = renderObject.localToGlobal(Offset.zero);
      final bottomRight = renderObject
          .localToGlobal(renderObject.size.bottomRight(Offset.zero));
      if (Rect.fromPoints(topLeft, bottomRight).contains(globalPosition)) {
        _applyDragValue(entry.key);
        return;
      }
    }
  }

  void _endCheckmarkDrag() {
    _dragValue = null;
    _draggedCheckmarks.clear();
  }

  Widget _buildDraggableIcon(int index, IconData icon) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _startCheckmarkDrag(index),
      onLongPressMoveUpdate: (details) =>
          _continueCheckmarkDrag(details.globalPosition),
      onLongPressEnd: (_) => _endCheckmarkDrag(),
      onLongPressCancel: _endCheckmarkDrag,
      child: Icon(icon, color: Colors.red),
    );
  }

  Widget buildCheckmark(BuildContext context, int index,
      {bool tooltipBelow = true}) {
    var checkMark = widget.checkMarks[index];
    var key = widget.validKeys[index];
    var localizations = AppLocalizations.of(context)!;

    switch (checkMark) {
      case ChameleonKeyCheckmark.found:
        return Tooltip(
          message: bytesToHex(key).toUpperCase(),
          preferBelow: tooltipBelow,
          child: const Icon(
            Icons.check,
            color: Colors.green,
          ),
        );
      case ChameleonKeyCheckmark.none:
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: _buildDraggableIcon(index, Icons.close),
          tooltip: localizations.skip_recovery,
          onPressed: widget.onCheckmarkChanged != null
              ? () {
                  widget.onCheckmarkChanged!(
                      index, ChameleonKeyCheckmark.disabled);
                }
              : null,
        );
      case ChameleonKeyCheckmark.disabled:
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: _buildDraggableIcon(index, Icons.cancel),
          tooltip: localizations.resume_recovery,
          onPressed: widget.onCheckmarkChanged != null
              ? () {
                  widget.onCheckmarkChanged!(index, ChameleonKeyCheckmark.none);
                }
              : null,
        );
      case ChameleonKeyCheckmark.checking:
        return const CircularProgressIndicator();
    }
  }

  List<Widget> buildCheckmarkRow(int checkmarkIndex, int count) {
    return [
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          double maxWidth = constraints.maxWidth;

          double requiredWidth =
              (count * (widget.checkmarkSize + 4)) + 30; // Rough estimate

          double scaleFactor = requiredWidth > maxWidth
              ? maxWidth / requiredWidth
              : 1.0; // Calculate scale factor

          return Transform.scale(
            scale: scaleFactor,
            child: buildContent(checkmarkIndex, count),
          );
        },
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget buildContent(int checkmarkIndex, int count) {
    return Column(
      children: [
        Row(
          children: [
            const Text("     "),
            ...List.generate(
              count,
              (index) => Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(
                  width: widget.checkmarkSize,
                  height: widget.checkmarkSize,
                  child: Center(
                    child: Text("${checkmarkIndex + index} ",
                        style: TextStyle(fontSize: widget.fontSize)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Transform(
              transform: Matrix4.translationValues(0.0, 1.0, 0.0),
              child: Text(
                "A",
                style: TextStyle(fontSize: widget.fontSize),
              ),
            ),
            ...List.generate(
              count,
              (index) => Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(
                  key: _checkmarkKey(checkmarkIndex + index),
                  width: widget.checkmarkSize,
                  height: widget.checkmarkSize,
                  child: buildCheckmark(context, checkmarkIndex + index,
                      tooltipBelow: false),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Transform(
              transform: Matrix4.translationValues(0.0, 1.0, 0.0),
              child: Text(
                "B",
                style: TextStyle(fontSize: widget.fontSize),
              ),
            ),
            ...List.generate(
              count,
              (index) => Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(
                  key: _checkmarkKey(40 + checkmarkIndex + index),
                  width: widget.checkmarkSize,
                  height: widget.checkmarkSize,
                  child: buildCheckmark(context, 40 + checkmarkIndex + index,
                      tooltipBelow: true),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (int i = 0; i < widget.checkmarkCount; i += widget.checkmarkPerRow)
        Column(children: [
          ...buildCheckmarkRow(
              i, min(widget.checkmarkPerRow, widget.checkmarkCount - i))
        ])
    ]);
  }
}
