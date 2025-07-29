import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

class MifareUltralightDumpHighlighter {
  static Color getUidColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.purple.shade300
        : Colors.purple.shade700;
  }

  static Color getBccColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.orange.shade300
        : Colors.orange.shade700;
  }

  static Color getLockColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.red.shade300
        : Colors.red.shade700;
  }

  static Color getPasswordColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.lightGreen.shade300
        : Colors.lightGreen.shade700;
  }

  static Color getDefaultColor(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
  }

  static List<TextSpan> highlightBlock(String blockData, int blockNumber,
      BuildContext context, CardSave cardSave) {
    if (blockNumber == 0) {
      return highlightFirstUidBlock(blockData, context);
    } else if (blockNumber < 2) {
      return highlightUidBlock(blockData, context);
    } else if (blockNumber == 2) {
      return highlightBccBlock(blockData, context);
    } else if (blockNumber == mfUltralightGetPasswordPage(cardSave.tag)) {
      return highlightPasswordBlock(blockData, context);
    } else {
      return highlightDataBlock(blockData, context);
    }
  }

  static List<TextSpan> highlightUidBlock(
      String blockData, BuildContext context) {
    return [
      TextSpan(
          text: blockData,
          style: TextStyle(
              color: getUidColor(context), fontWeight: FontWeight.bold))
    ];
  }

  static List<TextSpan> highlightFirstUidBlock(
      String blockData, BuildContext context) {
    List<TextSpan> spans = [];
    String cleanData = blockData.replaceAll(' ', '');
    if (cleanData.length == 8) {
      String spacedData = _addSpacesToHex(cleanData);
      String uidPart = spacedData.substring(0, 8);
      String bccPart = spacedData.substring(8);
      spans.add(TextSpan(
        text: uidPart,
        style: TextStyle(
          color: getUidColor(context),
          fontWeight: FontWeight.bold,
        ),
      ));
      spans.add(TextSpan(
        text: bccPart,
        style: TextStyle(
          color: getBccColor(context),
          fontWeight: FontWeight.bold,
        ),
      ));
    } else {
      spans.add(TextSpan(
          text: blockData, style: TextStyle(color: getDefaultColor(context))));
    }
    return spans;
  }

  static List<TextSpan> highlightBccBlock(
      String blockData, BuildContext context) {
    List<TextSpan> spans = [];
    String cleanData = blockData.replaceAll(' ', '');
    if (cleanData.length == 8) {
      String spacedData = _addSpacesToHex(cleanData);
      spans.add(TextSpan(
          text: spacedData.substring(0, 2),
          style: TextStyle(
              color: getBccColor(context), fontWeight: FontWeight.bold)));
      spans.add(TextSpan(
          text: spacedData.substring(2, 5),
          style: TextStyle(color: getDefaultColor(context))));
      spans.add(TextSpan(
          text: spacedData.substring(5),
          style: TextStyle(
              color: getLockColor(context), fontWeight: FontWeight.bold)));
    } else {
      spans.add(TextSpan(
          text: blockData, style: TextStyle(color: getDefaultColor(context))));
    }
    return spans;
  }

  static List<TextSpan> highlightDataBlock(
      String blockData, BuildContext context) {
    return [
      TextSpan(
          text: blockData, style: TextStyle(color: getDefaultColor(context)))
    ];
  }

  static List<TextSpan> highlightPasswordBlock(
      String blockData, BuildContext context) {
    return [
      TextSpan(
          text: blockData,
          style: TextStyle(
              color: getPasswordColor(context), fontWeight: FontWeight.bold))
    ];
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
