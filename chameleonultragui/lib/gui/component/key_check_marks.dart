import 'dart:math';

import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:flutter/material.dart';

class KeyCheckMarks extends StatelessWidget {
  final int checkmarkCount;
  final List<ChameleonKeyCheckmark> checkMarks;
  final int checkmarkPerRow;
  final double checkmarkSize;
  final double fontSize;

  const KeyCheckMarks(
      {super.key,
      required this.checkMarks,
      this.checkmarkCount = 16,
      this.checkmarkPerRow = 16,
      this.checkmarkSize = 20,
      this.fontSize = 16});

  Widget buildCheckmark(ChameleonKeyCheckmark value) {
    if (value != ChameleonKeyCheckmark.checking) {
      return Icon(
        value == ChameleonKeyCheckmark.found ? Icons.check : Icons.close,
        color: value == ChameleonKeyCheckmark.found ? Colors.green : Colors.red,
      );
    } else {
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
              (count * (checkmarkSize + 4)) + 30; // Rough estimate

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
                  width: checkmarkSize,
                  height: checkmarkSize,
                  child: Center(
                    child: Text("${checkmarkIndex + index} ",
                        style: TextStyle(fontSize: fontSize)),
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
                style: TextStyle(fontSize: fontSize),
              ),
            ),
            ...List.generate(
              count,
              (index) => Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(
                  width: checkmarkSize,
                  height: checkmarkSize,
                  child: buildCheckmark(checkMarks[checkmarkIndex + index]),
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
                style: TextStyle(fontSize: fontSize),
              ),
            ),
            ...List.generate(
              count,
              (index) => Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(
                  width: checkmarkSize,
                  height: checkmarkSize,
                  child:
                      buildCheckmark(checkMarks[40 + checkmarkIndex + index]),
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
      for (int i = 0; i < checkmarkCount; i += checkmarkPerRow)
        Column(children: [
          ...buildCheckmarkRow(i, min(checkmarkPerRow, checkmarkCount - i))
        ])
    ]);
  }
}
