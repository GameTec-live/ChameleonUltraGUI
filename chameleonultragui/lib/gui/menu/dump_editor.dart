import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_highlighter.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/dump_highlighter.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/dump_analyzer.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class DumpEditor extends StatefulWidget {
  final CardSave cardSave;
  final Function(List<Uint8List>) onSave;

  const DumpEditor({
    super.key,
    required this.cardSave,
    required this.onSave,
  });

  @override
  DumpEditorState createState() => DumpEditorState();
}

class DumpEditorState extends State<DumpEditor> {
  late List<Uint8List> dumpData;
  late List<TextEditingController> controllers;
  late List<String> initialTexts;
  bool hasUnsavedChanges = false;
  bool isInsertMode = false;
  ScrollController scrollController = ScrollController();
  late bool isUltralight;
  late int bytesPerBlock;
  late int hexCharsPerBlock;

  @override
  void initState() {
    super.initState();
    isUltralight = isMifareUltralight(widget.cardSave.tag);
    bytesPerBlock = isUltralight ? 4 : 16;
    hexCharsPerBlock = bytesPerBlock * 2;
    initEditor();
  }

  @override
  void dispose() {
    for (var controller in controllers) {
      controller.dispose();
    }
    scrollController.dispose();
    super.dispose();
  }

  void initEditor() {
    dumpData =
        widget.cardSave.data.map((bytes) => Uint8List.fromList(bytes)).toList();
    controllers = [];
    initialTexts = [];

    if (isUltralight) {
      _initUltralightEditor();
    } else {
      _initClassicEditor();
    }
  }

  void _initUltralightEditor() {
    TextEditingController controller = TextEditingController();
    String dumpText = '';
    for (int i = 0; i < dumpData.length; i++) {
      if (i > 0) dumpText += '\n';
      dumpText += _formatHexData(dumpData[i]);
    }
    controller.text = dumpText;
    controller.addListener(() => _onDataChanged(0));
    controllers.add(controller);
    initialTexts.add(dumpText);
  }

  void _initClassicEditor() {
    MifareClassicType cardType =
        chameleonTagTypeGetMfClassicType(widget.cardSave.tag);
    int sectorCount = mfClassicGetSectorCount(cardType);

    for (int sector = 0; sector < sectorCount; sector++) {
      int blocksPerSector = mfClassicGetBlockCountBySector(sector);
      int firstBlock = mfClassicGetFirstBlockCountBySector(sector);

      String sectorText = '';
      for (int block = 0; block < blocksPerSector; block++) {
        int blockIndex = firstBlock + block;
        if (blockIndex < dumpData.length && dumpData[blockIndex].isNotEmpty) {
          if (block > 0) sectorText += '\n';
          sectorText += _formatHexData(dumpData[blockIndex]);
        }
      }

      TextEditingController controller =
          TextEditingController(text: sectorText);
      controller.addListener(() => _onDataChanged(sector));
      controllers.add(controller);
      initialTexts.add(sectorText);
    }
  }

  String _formatHexData(Uint8List data) {
    String hexData = bytesToHex(data).toUpperCase();
    String spacedHex = '';
    for (int i = 0; i < hexData.length; i += 2) {
      if (i > 0) spacedHex += ' ';
      spacedHex += hexData.substring(i, i + 2);
    }
    return spacedHex;
  }

  void _onDataChanged(int index) {
    if (index < controllers.length && index < initialTexts.length) {
      String currentText = controllers[index].text;
      String initialText = initialTexts[index];

      if (currentText != initialText) {
        setState(() {
          hasUnsavedChanges = true;
        });
      }
    }
  }

  TextEditingValue _handleTextInput(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (isInsertMode) {
      return _handleInsertMode(oldValue, newValue);
    } else {
      return _handleOverwriteMode(oldValue, newValue);
    }
  }

  TextEditingValue _handleInsertMode(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= oldValue.text.length) {
      return _handleDeletion(oldValue, newValue);
    }

    String oldText = oldValue.text;
    String newText = newValue.text;
    int insertionPos = oldValue.selection.baseOffset;

    // Find what was inserted
    String insertedText = '';
    if (newText.length > oldText.length) {
      int insertLength = newText.length - oldText.length;
      insertedText =
          newText.substring(insertionPos, insertionPos + insertLength);
    }

    // Remove any non-hex characters from insertion
    insertedText = insertedText.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');

    if (insertedText.isEmpty) {
      return _processTextWithSpacing(newValue);
    }

    // Find which line we're inserting into
    List<String> lines = oldText.split('\n');
    int currentPos = 0;
    int lineIndex = 0;
    int posInLine = 0;

    for (int i = 0; i < lines.length; i++) {
      if (currentPos + lines[i].length >= insertionPos) {
        lineIndex = i;
        posInLine = insertionPos - currentPos;
        break;
      }
      currentPos += lines[i].length + 1; // +1 for newline
    }

    if (lineIndex >= lines.length) {
      return _processTextWithSpacing(newValue);
    }

    String line = lines[lineIndex];
    String cleanLine = line.replaceAll(' ', '');

    // Calculate position in clean line
    int cleanPos = 0;
    for (int i = 0; i < posInLine && i < line.length; i++) {
      if (line[i] != ' ') {
        cleanPos++;
      }
    }

    // Insert characters into clean line
    String newCleanLine = cleanLine.substring(0, cleanPos) +
        insertedText +
        cleanLine.substring(cleanPos);

    // Limit to hex chars per block
    if (newCleanLine.length > hexCharsPerBlock) {
      newCleanLine = newCleanLine.substring(0, hexCharsPerBlock);
    }

    // Re-add spacing
    String newSpacedLine = '';
    for (int i = 0; i < newCleanLine.length; i += 2) {
      if (i > 0) newSpacedLine += ' ';
      newSpacedLine += newCleanLine.substring(i, i + 2);
    }

    // Update the line
    lines[lineIndex] = newSpacedLine;

    // Calculate new cursor position
    int newCleanPos = cleanPos + insertedText.length;
    int newSpacedPos =
        newCleanPos + (newCleanPos > 0 ? (newCleanPos - 1) ~/ 2 : 0);

    int newCursorPos = currentPos + newSpacedPos;
    if (newSpacedPos > newSpacedLine.length) {
      newCursorPos--;
    }

    String finalText = lines.join('\n').toUpperCase();

    return TextEditingValue(
      text: finalText,
      selection: TextSelection.collapsed(
          offset: newCursorPos.clamp(0, finalText.length)),
    );
  }

  TextEditingValue _handleOverwriteMode(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= oldValue.text.length) {
      return _handleDeletion(oldValue, newValue);
    }

    String oldText = oldValue.text;
    String newText = newValue.text;
    int insertionPos = oldValue.selection.baseOffset;

    // Find what was typed
    String typedText = '';
    if (newText.length > oldText.length) {
      int insertLength = newText.length - oldText.length;
      typedText = newText.substring(insertionPos, insertionPos + insertLength);
    }

    // Remove any non-hex characters from typed text
    typedText = typedText.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');

    if (typedText.isEmpty) {
      return _processTextWithSpacing(newValue);
    }

    // Find which line we're typing into
    List<String> lines = oldText.split('\n');
    int currentPos = 0;
    int lineIndex = 0;
    int posInLine = 0;

    for (int i = 0; i < lines.length; i++) {
      if (currentPos + lines[i].length >= insertionPos) {
        lineIndex = i;
        posInLine = insertionPos - currentPos;
        break;
      }
      currentPos += lines[i].length + 1; // +1 for newline
    }

    if (lineIndex >= lines.length) {
      return _processTextWithSpacing(newValue);
    }

    String line = lines[lineIndex];
    String cleanLine = line.replaceAll(' ', '');

    // Calculate position in clean line
    int cleanPos = 0;
    for (int i = 0; i < posInLine && i < line.length; i++) {
      if (line[i] != ' ') {
        cleanPos++;
      }
    }

    // In overwrite mode, replace characters instead of inserting them
    String newCleanLine = cleanLine;
    for (int i = 0;
        i < typedText.length && cleanPos + i < cleanLine.length;
        i++) {
      if (cleanPos + i < newCleanLine.length) {
        newCleanLine = newCleanLine.substring(0, cleanPos + i) +
            typedText[i] +
            newCleanLine.substring(cleanPos + i + 1);
      }
    }

    // If we're at the end of the line, we can extend it up to the limit
    if (cleanPos >= cleanLine.length &&
        newCleanLine.length < hexCharsPerBlock) {
      int remainingChars = hexCharsPerBlock - newCleanLine.length;
      int charsToAdd =
          typedText.length < remainingChars ? typedText.length : remainingChars;
      newCleanLine += typedText.substring(0, charsToAdd);
    }

    // Limit to hex chars per block
    if (newCleanLine.length > hexCharsPerBlock) {
      newCleanLine = newCleanLine.substring(0, hexCharsPerBlock);
    }

    // Re-add spacing
    String newSpacedLine = '';
    for (int i = 0; i < newCleanLine.length; i += 2) {
      if (i > 0) newSpacedLine += ' ';
      newSpacedLine += newCleanLine.substring(i, i + 2);
    }

    // Update the line
    lines[lineIndex] = newSpacedLine;

    // Calculate new cursor position
    int newCleanPos = cleanPos + typedText.length;
    if (newCleanPos > newCleanLine.length) {
      newCleanPos = newCleanLine.length;
    }
    int newSpacedPos =
        newCleanPos + (newCleanPos > 0 ? (newCleanPos - 1) ~/ 2 : 0);

    int newCursorPos = currentPos + newSpacedPos;

    String finalText = lines.join('\n').toUpperCase();

    return TextEditingValue(
      text: finalText,
      selection: TextSelection.collapsed(
          offset: newCursorPos.clamp(0, finalText.length)),
    );
  }

  TextEditingValue _handleDeletion(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: oldValue.text,
      selection: TextSelection.collapsed(
          offset: oldValue.selection.baseOffset.clamp(0, oldValue.text.length)),
    );
  }

  TextEditingValue _processTextWithSpacing(TextEditingValue value) {
    List<String> lines = value.text.split('\n');
    List<String> processedLines = [];

    int oldCursorPos = value.selection.baseOffset;
    int newCursorPos = oldCursorPos;
    int currentPos = 0;
    int processedPos = 0;

    for (String line in lines) {
      String cleanLine = line.replaceAll(' ', '');

      if (cleanLine.length > hexCharsPerBlock) {
        cleanLine = cleanLine.substring(0, hexCharsPerBlock);
      }

      String spacedLine = '';
      for (int i = 0; i < cleanLine.length; i += 2) {
        if (i > 0) spacedLine += ' ';
        spacedLine += cleanLine.substring(i, i + 2);
      }
      processedLines.add(spacedLine);

      int lineStartPos = currentPos;
      int lineEndPos = currentPos + line.length;
      int processedLineStartPos = processedPos;
      int processedLineEndPos = processedPos + spacedLine.length;

      if (oldCursorPos >= lineStartPos && oldCursorPos <= lineEndPos) {
        int relativePos = oldCursorPos - lineStartPos;
        int cleanRelativePos = 0;
        int originalIndex = 0;

        for (int i = 0; i < line.length && originalIndex < relativePos; i++) {
          if (line[i] != ' ') {
            cleanRelativePos++;
          }
          originalIndex++;
        }

        int spacedRelativePos = 0;
        for (int i = 0; i < cleanRelativePos; i++) {
          if (i > 0 && i % 2 == 0) {
            spacedRelativePos++;
          }
          spacedRelativePos++;
        }

        newCursorPos = processedLineStartPos +
            spacedRelativePos.clamp(0, spacedLine.length);
      }

      currentPos = lineEndPos + 1;
      processedPos = processedLineEndPos + 1;
    }

    String processedText = processedLines.join('\n').toUpperCase();

    return TextEditingValue(
      text: processedText,
      selection: TextSelection.collapsed(
          offset: newCursorPos.clamp(0, processedText.length)),
    );
  }

  bool _validateDataForSave(String data, int controllerIndex) {
    List<String> lines = data.split('\n');

    if (isUltralight) {
      for (String line in lines) {
        String cleanLine = line.replaceAll(' ', '').trim();
        if (cleanLine.isNotEmpty &&
            !RegExp(r'^[0-9A-Fa-f-]{8}$').hasMatch(cleanLine)) {
          return false;
        }
      }
    } else {
      int expectedBlocks = mfClassicGetBlockCountBySector(controllerIndex);
      if (lines.length != expectedBlocks) {
        return false;
      }

      for (String line in lines) {
        String cleanLine = line.replaceAll(' ', '').trim();
        if (!RegExp(r'^[0-9A-Fa-f-]{32}$').hasMatch(cleanLine)) {
          return false;
        }
      }
    }

    return true;
  }

  void _showErrorDialog(String message) {
    var localizations = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.error),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.ok),
          ),
        ],
      ),
    );
  }

  void _saveDump() {
    var localizations = AppLocalizations.of(context)!;
    List<Uint8List> updatedDump = List.from(dumpData);

    if (isUltralight) {
      List<String> lines = controllers[0].text.split('\n');
      for (int i = 0; i < lines.length; i++) {
        String hexData = lines[i].replaceAll(' ', '').trim().toUpperCase();
        if (hexData.length != 8) {
          _showErrorDialog('${localizations.invalid_data_in_block} $i');
          return;
        }
        if (hexData != '-' * 8) {
          updatedDump[i] = hexToBytes(hexData);
        }
      }
      initialTexts[0] = controllers[0].text;
    } else {
      for (int sector = 0; sector < controllers.length; sector++) {
        if (!_validateDataForSave(controllers[sector].text, sector)) {
          _showErrorDialog('${localizations.invalid_data_in_sector} $sector');
          return;
        }

        List<String> lines = controllers[sector].text.split('\n');
        int firstBlock = mfClassicGetFirstBlockCountBySector(sector);

        for (int block = 0; block < lines.length; block++) {
          int blockIndex = firstBlock + block;
          if (blockIndex < updatedDump.length) {
            String hexData =
                lines[block].replaceAll(' ', '').trim().toUpperCase();
            if (hexData != '-' * 32) {
              updatedDump[blockIndex] = hexToBytes(hexData);
            }
          }
        }
        initialTexts[sector] = controllers[sector].text;
      }
    }

    widget.onSave(updatedDump);
    setState(() {
      hasUnsavedChanges = false;
    });
    Navigator.pop(context);
  }

  void _cancelEdit() {
    if (hasUnsavedChanges) {
      var localizations = AppLocalizations.of(context)!;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(localizations.unsaved_changes),
          content: Text(localizations.unsaved_changes_message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: Text(localizations.discard),
            ),
          ],
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _showAsciiView() {
    var localizations = AppLocalizations.of(context)!;
    List<String> asciiData = [];

    if (isUltralight) {
      List<String> lines = controllers[0].text.split('\n');
      for (int i = 0; i < lines.length; i++) {
        String hexData = lines[i].replaceAll(' ', '').trim();
        if (hexData.isNotEmpty) {
          String ascii = MifareUltralightDumpAnalyzer.hexToAscii(hexData);
          asciiData.add('${localizations.block} $i: $ascii');
        }
      }
    } else {
      for (int sector = 0; sector < controllers.length; sector++) {
        List<String> lines = controllers[sector].text.split('\n');
        asciiData.add('${localizations.sector}: $sector');
        for (int block = 0; block < lines.length; block++) {
          String hexData = lines[block].replaceAll(' ', '').trim();
          if (hexData.isNotEmpty) {
            String ascii = MifareClassicDumpAnalyzer.hexToAscii(hexData);
            asciiData.add('${localizations.block} $block: $ascii');
          }
        }
        asciiData.add('');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.ascii_view),
        content: SizedBox(
          width: 400,
          height: 300,
          child: SingleChildScrollView(
            child: Text(
              asciiData.join('\n'),
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  void _showAccessConditions() {
    if (isUltralight) return;
    var localizations = AppLocalizations.of(context)!;

    List<String> acData = [];
    for (int sector = 0; sector < controllers.length; sector++) {
      List<String> lines = controllers[sector].text.split('\n');
      if (lines.isNotEmpty) {
        String sectorTrailer = lines.last.replaceAll(' ', '').trim();
        if (sectorTrailer.length >= 20) {
          String accessConditions = sectorTrailer.substring(12, 20);
          Map<String, dynamic> decoded =
              MifareClassicDumpAnalyzer.decodeAccessConditions(
                  accessConditions, context);

          acData.add('${localizations.sector} $sector:');
          if (decoded['readable']) {
            Map<String, String> access = decoded['access'];
            access.forEach((key, value) {
              acData.add('  $key: $value');
            });
          } else {
            acData.add('  ${localizations.error}: ${decoded['error']}');
          }
          acData.add('');
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.access_conditions),
        content: SizedBox(
          width: 500,
          height: 400,
          child: SingleChildScrollView(
            child: Text(
              acData.join('\n'),
              style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  void _showValueBlocks() {
    if (isUltralight) return;
    var localizations = AppLocalizations.of(context)!;

    List<String> valueData = [];
    bool foundValueBlocks = false;

    for (int sector = 0; sector < controllers.length; sector++) {
      List<String> lines = controllers[sector].text.split('\n');
      for (int block = 0; block < lines.length; block++) {
        String hexData = lines[block].replaceAll(' ', '').trim();
        if (hexData.isNotEmpty) {
          int? value = MifareClassicDumpAnalyzer.valueBlockToInt(hexData);
          if (value != null) {
            foundValueBlocks = true;
            valueData.add(
                '${localizations.sector} $sector, ${localizations.block} $block: $value');
          }
        }
      }
    }

    if (!foundValueBlocks) {
      valueData.add(localizations.no_value_blocks_found);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.value_blocks),
        content: SizedBox(
          width: 300,
          height: 200,
          child: SingleChildScrollView(
            child: Text(
              valueData.join('\n'),
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildHighlightedTextOnly(int controllerIndex) {
    List<String> lines = controllers[controllerIndex].text.split('\n');
    List<TextSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '\n'));
      }

      if (line.isEmpty) {
        spans.add(TextSpan(
          text: '',
          style: TextStyle(color: _getDefaultHighlightColor()),
        ));
        continue;
      }

      List<TextSpan> lineSpans =
          _getHighlightedLineSpans(line, controllerIndex, i);
      spans.addAll(lineSpans);
    }

    return spans;
  }

  List<TextSpan> _buildBlockNumbers(int controllerIndex) {
    List<String> lines = controllers[controllerIndex].text.split('\n');
    List<TextSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '\n'));
      }

      int blockNumber = isUltralight
          ? i
          : mfClassicGetFirstBlockCountBySector(controllerIndex) + i;
      String blockNumberStr = blockNumber.toString().padLeft(3, ' ');
      spans.add(TextSpan(
        text: '$blockNumberStr: ',
        style: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade400
              : Colors.grey.shade600,
          fontWeight: FontWeight.normal,
        ),
      ));
    }

    return spans;
  }

  List<TextSpan> _getHighlightedLineSpans(
      String line, int controllerIndex, int lineIndex) {
    if (line.isEmpty) {
      return [
        TextSpan(text: '', style: TextStyle(color: _getDefaultHighlightColor()))
      ];
    }

    if (isUltralight) {
      return MifareUltralightDumpHighlighter.highlightBlock(
          line, lineIndex, context, widget.cardSave);
    } else {
      int blocksPerSector = mfClassicGetBlockCountBySector(controllerIndex);
      bool isSectorTrailer = lineIndex == blocksPerSector - 1;
      bool isFirstBlock = controllerIndex == 0 && lineIndex == 0;

      if (isSectorTrailer) {
        return MifareClassicDumpHighlighter.highlightSectorTrailer(
            line, context);
      } else if (isFirstBlock) {
        return MifareClassicDumpHighlighter.highlightFirstBlock(line, context);
      } else {
        return MifareClassicDumpHighlighter.highlightDataBlock(line, context);
      }
    }
  }

  Color _getDefaultHighlightColor() {
    return isUltralight
        ? MifareUltralightDumpHighlighter.getDefaultColor(context)
        : MifareClassicDumpHighlighter.getDefaultColor(context);
  }

  Widget _buildAdaptiveEditor(int controllerIndex) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double optimalFontSize =
            _guessOptimalFontSize(controllerIndex, context);
        return _buildOriginalEditor(controllerIndex, fontSize: optimalFontSize);
      },
    );
  }

  double _guessOptimalFontSize(int controllerIndex, BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    double maxWidth = isUltralight ? 145 : 395;
    double actualWidth = screenWidth < maxWidth ? screenWidth : maxWidth;

    double availableWidth = actualWidth - 28;

    String sampleText = _getLongestLine(controllerIndex);
    if (sampleText.isEmpty) {
      return 14.0;
    }

    for (double fontSize = 16.0; fontSize >= 10.0; fontSize -= 0.1) {
      if (_doesTextFitOnOneLine(sampleText, fontSize, availableWidth)) {
        return fontSize;
      }
    }

    return 10.0;
  }

  double _calculateLeftPadding(BuildContext context, double fontSize) {
    final TextPainter blockNumberPainter = TextPainter(
      text: TextSpan(
        text: '999: ',
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: fontSize,
          height: 1.2,
          letterSpacing: 0.0,
          fontWeight: FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    blockNumberPainter.layout();

    return blockNumberPainter.size.width - 1;
  }

  String _getLongestLine(int controllerIndex) {
    if (controllerIndex >= controllers.length) return '';

    List<String> lines = controllers[controllerIndex].text.split('\n');
    String longestLine = '';

    for (String line in lines) {
      String trimmedLine = line.trim();
      if (trimmedLine.length > longestLine.length) {
        longestLine = trimmedLine;
      }
    }

    return '999: $longestLine';
  }

  bool _doesTextFitOnOneLine(
      String text, double fontSize, double availableWidth) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: fontSize,
          height: 1.2,
          letterSpacing: 0.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );

    textPainter.layout(maxWidth: availableWidth);

    bool fitsInLines = !textPainter.didExceedMaxLines;
    bool fitsInWidth = textPainter.size.width <= availableWidth;

    return fitsInLines && fitsInWidth;
  }

  Widget _buildOriginalEditor(int controllerIndex, {double fontSize = 14.0}) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: IgnorePointer(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: fontSize,
                        height: 1.2,
                        letterSpacing: 0.0,
                      ),
                      children: _buildBlockNumbers(controllerIndex),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: fontSize,
                          height: 1.2,
                          letterSpacing: 0.0,
                        ),
                        children: _buildHighlightedTextOnly(controllerIndex),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _calculateLeftPadding(context, fontSize),
              ),
              Expanded(
                child: TextFormField(
                  controller: controllers[controllerIndex],
                  maxLines: null,
                  style: TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: fontSize,
                    color: Colors.transparent,
                    height: 1.2,
                    letterSpacing: 0.0,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '',
                    isDense: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9A-Fa-f\n\s-]')),
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      return _handleTextInput(oldValue, newValue);
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(int controllerIndex) {
    var localizations = AppLocalizations.of(context)!;
    String title = isUltralight
        ? localizations.dump
        : '${localizations.sector}: $controllerIndex';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).primaryColor,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).inputDecorationTheme.fillColor ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade100),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.shade600
                  : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: _buildAdaptiveEditor(controllerIndex),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildColorLegend() {
    var localizations = AppLocalizations.of(context)!;

    List<Widget> legendItems = [];

    if (isUltralight) {
      legendItems = [
        _buildLegendItem(localizations.uid,
            MifareUltralightDumpHighlighter.getUidColor(context)),
        _buildLegendItem(localizations.bcc,
            MifareUltralightDumpHighlighter.getBccColor(context)),
        _buildLegendItem(localizations.lock_bytes,
            MifareUltralightDumpHighlighter.getLockColor(context)),
        _buildLegendItem(localizations.password,
            MifareUltralightDumpHighlighter.getPasswordColor(context)),
        _buildLegendItem(
            localizations.block_index,
            Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade400
                : Colors.grey.shade600),
      ];
    } else {
      legendItems = [
        _buildLegendItem(localizations.uid,
            MifareClassicDumpHighlighter.getUidColor(context)),
        _buildLegendItem(localizations.value_block,
            MifareClassicDumpHighlighter.getValueBlockColor(context)),
        _buildLegendItem("${localizations.key} A",
            MifareClassicDumpHighlighter.getKeyAColor(context)),
        _buildLegendItem("${localizations.key} B",
            MifareClassicDumpHighlighter.getKeyBColor(context)),
        _buildLegendItem(localizations.access_conditions,
            MifareClassicDumpHighlighter.getAccessConditionsColor(context)),
        _buildLegendItem(
            localizations.block_index,
            Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade400
                : Colors.grey.shade600),
      ];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                localizations.color_legend,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getDefaultHighlightColor(),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${localizations.insert_mode}: ',
                    style: TextStyle(
                      color: _getDefaultHighlightColor(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Switch(
                    value: isInsertMode,
                    onChanged: (value) {
                      setState(() {
                        isInsertMode = value;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: legendItems,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: _getDefaultHighlightColor()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return PopScope(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && hasUnsavedChanges) {
          _cancelEdit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.dump_editor),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancelEdit,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _cancelEdit,
              tooltip: localizations.cancel,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveDump,
              tooltip: localizations.save,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 395),
                      child: _buildColorLegend(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(
                    controllers.length,
                    (index) => Center(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: isUltralight ? 145 : 395),
                        child: _buildEditor(index),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade600
                        : Colors.grey.shade300,
                  ),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _showAsciiView,
                    child: Text(localizations.ascii),
                  ),
                  if (!isUltralight) ...[
                    ElevatedButton(
                      onPressed: _showAccessConditions,
                      child: Text(localizations.acl),
                    ),
                    ElevatedButton(
                      onPressed: _showValueBlocks,
                      child: Text(localizations.value),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
