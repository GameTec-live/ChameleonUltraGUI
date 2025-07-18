import 'package:flutter/material.dart';
import 'dart:typed_data';

class MifareClassicDumpHighlighter {
  static Color getUidColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.purple.shade300
        : Colors.purple.shade700;
  }

  static Color getKeyAColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.lightGreen.shade300
        : Colors.lightGreen.shade700;
  }

  static Color getKeyBColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade700;
  }

  static Color getAccessConditionsColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.orange.shade300
        : Colors.orange.shade700;
  }

  static Color getValueBlockColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.yellow.shade300
        : Colors.yellow.shade700;
  }

  static Color getDefaultColor(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
  }

  static const Color uidColor = Colors.purple;
  static const Color keyAColor = Colors.lightGreen;
  static const Color keyBColor = Colors.green;
  static const Color accessConditionsColor = Colors.orange;
  static const Color valueBlockColor = Colors.yellow;

  static List<TextSpan> highlightSector(
      String sectorData, int sector, BuildContext context) {
    List<String> lines = sectorData.split('\n');
    List<TextSpan> spans = [];

    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      String line = lines[lineIndex].trim();

      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '\n'));
      }

      if (line.isEmpty) {
        spans.add(TextSpan(
          text: '',
          style: TextStyle(color: getDefaultColor(context)),
        ));
        continue;
      }

      bool isSectorTrailer = lineIndex == lines.length - 1;

      bool isFirstBlock = sector == 0 && lineIndex == 0;

      if (isSectorTrailer) {
        spans.addAll(highlightSectorTrailer(line, context));
      } else if (isFirstBlock) {
        spans.addAll(highlightFirstBlock(line, context));
      } else {
        spans.addAll(highlightDataBlock(line, context));
      }
    }

    return spans;
  }

  static List<TextSpan> highlightSectorTrailer(
      String trailerData, BuildContext context) {
    List<TextSpan> spans = [];

    try {
      String cleanData = trailerData.replaceAll(' ', '');

      if (cleanData.length == 32) {
        String spacedData = _addSpacesToHex(cleanData);

        String keyA = spacedData.substring(0, 17); // "XX XX XX XX XX XX"
        spans.add(TextSpan(
          text: keyA,
          style: TextStyle(
            color: getKeyAColor(context),
            fontWeight: FontWeight.bold,
          ),
        ));

        String ac = spacedData.substring(17, 29); // " XX XX XX XX"
        spans.add(TextSpan(
          text: ac,
          style: TextStyle(
            color: getAccessConditionsColor(context),
            fontWeight: FontWeight.bold,
          ),
        ));

        String keyB = spacedData.substring(29); // " XX XX XX XX XX XX"
        spans.add(TextSpan(
          text: keyB,
          style: TextStyle(
            color: getKeyBColor(context),
            fontWeight: FontWeight.bold,
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: trailerData,
          style: TextStyle(color: getDefaultColor(context)),
        ));
      }
    } catch (e) {
      spans.add(TextSpan(
        text: trailerData,
        style: TextStyle(color: getDefaultColor(context)),
      ));
    }

    return spans;
  }

  static List<TextSpan> highlightFirstBlock(
      String blockData, BuildContext context) {
    List<TextSpan> spans = [];

    try {
      String cleanData = blockData.replaceAll(' ', '');

      if (cleanData.length == 32) {
        String spacedData = _addSpacesToHex(cleanData);

        String uid = spacedData.substring(0, 11); // "XX XX XX XX"
        spans.add(TextSpan(
          text: uid,
          style: TextStyle(
            color: getUidColor(context),
            fontWeight: FontWeight.bold,
          ),
        ));

        String rest =
            spacedData.substring(11); // " XX XX XX XX XX XX XX XX XX XX XX XX"
        spans.add(TextSpan(
          text: rest,
          style: TextStyle(color: getDefaultColor(context)),
        ));
      } else {
        spans.add(TextSpan(
          text: blockData,
          style: TextStyle(color: getDefaultColor(context)),
        ));
      }
    } catch (e) {
      spans.add(TextSpan(
        text: blockData,
        style: TextStyle(color: getDefaultColor(context)),
      ));
    }

    return spans;
  }

  static List<TextSpan> highlightDataBlock(
      String blockData, BuildContext context) {
    List<TextSpan> spans = [];

    try {
      String cleanData = blockData.replaceAll(' ', '');

      if (cleanData.length == 32 && isValueBlock(cleanData)) {
        spans.add(TextSpan(
          text: blockData,
          style: TextStyle(
            color: getValueBlockColor(context),
            fontWeight: FontWeight.bold,
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: blockData,
          style: TextStyle(color: getDefaultColor(context)),
        ));
      }
    } catch (e) {
      spans.add(TextSpan(
        text: blockData,
        style: TextStyle(color: getDefaultColor(context)),
      ));
    }

    return spans;
  }

  static bool isValueBlock(String blockData) {
    if (blockData.length != 32) return false;

    try {
      Uint8List bytes = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        bytes[i] = int.parse(blockData.substring(i * 2, i * 2 + 2), radix: 16);
      }

      for (int i = 0; i < 4; i++) {
        if (bytes[i] != bytes[i + 8]) return false;
      }

      for (int i = 0; i < 4; i++) {
        if (bytes[i + 4] != (0xFF - bytes[i])) return false;
      }

      if (bytes[12] != bytes[14]) return false;
      if (bytes[13] != bytes[15]) return false;
      if (bytes[12] != (0xFF - bytes[13])) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  static TextSpan colorText(String text, Color color, {bool bold = false}) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  static Widget createHighlightedText(
      String text, int sector, BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: 14,
          color: getDefaultColor(context),
          height: 1.0,
        ),
        children: highlightSector(text, sector, context),
      ),
    );
  }

  static String _addSpacesToHex(String hex) {
    if (hex.isEmpty) return hex;

    String result = '';
    for (int i = 0; i < hex.length; i += 2) {
      if (i > 0) result += ' ';
      result += hex.substring(i, i + 2);
    }
    return result;
  }
}
