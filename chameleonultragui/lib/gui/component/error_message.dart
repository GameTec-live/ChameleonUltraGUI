import 'package:flutter/material.dart';

class ErrorMessage extends StatelessWidget {
  final String errorMessage;
  final double boxHeight;
  final double boxWidth;
  final Color iconColor;
  final double iconSize;
  final BorderRadius borderRadius;

  const ErrorMessage({
    super.key,
    required this.errorMessage,
    this.boxHeight = 60.0,
    this.boxWidth = double.infinity,
    this.iconColor = Colors.white,
    this.iconSize = 24.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
  });

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color boxColor = brightness == Brightness.light
        ? const Color(0xFFFDEDED)
        : const Color(0xFFFF7961);
    const Color textColor = Color(0xFF5F2120);

    return Container(
      height: boxHeight,
      width: boxWidth,
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: borderRadius,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(
            Icons.error_outline,
            color: textColor,
            size: iconSize,
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Text(
              errorMessage,
              style: const TextStyle(
                color: textColor,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
