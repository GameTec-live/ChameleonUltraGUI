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
import 'package:chameleonultragui/main.dart';
import 'package:provider/provider.dart';

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
  bool isCompareMode = false;
  List<Uint8List>? compareData;
  String compareName = '';
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
          offset: newValue.selection.baseOffset.clamp(0, oldValue.text.length)),
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

  void _replaceBlockHex(int controllerIndex, int lineIndex, String cleanHex) {
    List<String> lines = controllers[controllerIndex].text.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    lines[lineIndex] = _spaceHex(cleanHex.toUpperCase());
    controllers[controllerIndex].text = lines.join('\n');
  }

  Future<void> _showAsciiView() async {
    var localizations = AppLocalizations.of(context)!;
    List<int> sectorIndexes = [];
    List<int> lineIndexes = [];
    List<int> absoluteBlockIndexes = [];
    List<TextEditingController> asciiControllers = [];
    List<String> asciiInitialTexts = [];

    for (int sector = 0; sector < controllers.length; sector++) {
      List<String> lines = controllers[sector].text.split('\n');
      for (int line = 0; line < lines.length; line++) {
        String hex = lines[line].replaceAll(' ', '').trim();
        if (hex.length != hexCharsPerBlock || hex.contains('-')) continue;
        sectorIndexes.add(sector);
        lineIndexes.add(line);
        absoluteBlockIndexes.add(isUltralight
            ? line
            : mfClassicGetFirstBlockCountBySector(sector) + line);
        String ascii = isUltralight
            ? MifareUltralightDumpAnalyzer.hexToAscii(hex)
            : MifareClassicDumpAnalyzer.hexToAscii(hex);
        asciiControllers.add(TextEditingController(text: ascii));
        asciiInitialTexts.add(ascii);
      }
    }

    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(localizations.ascii_view),
          content: SizedBox(
            width: 420,
            height: 400,
            child: Column(
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: asciiControllers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => TextField(
                      controller: asciiControllers[index],
                      style: const TextStyle(fontFamily: 'RobotoMono'),
                      maxLength: bytesPerBlock,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[\x20-\x7E]')),
                        LengthLimitingTextInputFormatter(bytesPerBlock),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            '${localizations.block} ${absoluteBlockIndexes[index]}',
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () {
                for (int i = 0; i < asciiControllers.length; i++) {
                  if (asciiControllers[i].text != asciiInitialTexts[i] &&
                      asciiControllers[i].text.length != bytesPerBlock) {
                    setDialogState(() {
                      error = '${localizations.invalid_data_in_block} '
                          '${absoluteBlockIndexes[i]}; '
                          '$bytesPerBlock ASCII characters required.';
                    });
                    return;
                  }
                }
                for (int i = 0; i < asciiControllers.length; i++) {
                  if (asciiControllers[i].text == asciiInitialTexts[i]) {
                    continue;
                  }
                  String hex = asciiControllers[i]
                      .text
                      .codeUnits
                      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                      .join();
                  _replaceBlockHex(sectorIndexes[i], lineIndexes[i], hex);
                }
                Navigator.pop(dialogContext);
              },
              child: Text(localizations.save),
            ),
          ],
        ),
      ),
    );
    for (final controller in asciiControllers) {
      controller.dispose();
    }
  }

  Future<void> _showAccessConditions() async {
    if (isUltralight) return;
    var localizations = AppLocalizations.of(context)!;
    List<List<int>?> selections = [];
    List<List<List<int>>?> dataPermissions = [];
    List<List<List<int>>?> trailerPermissions = [];
    for (int sector = 0; sector < controllers.length; sector++) {
      List<String> lines = controllers[sector].text.split('\n');
      String trailer =
          lines.isEmpty ? '' : lines.last.replaceAll(' ', '').trim();
      List<int>? values;
      if (trailer.length == 32) {
        values = MifareClassicDumpAnalyzer.accessConditionValues(
                trailer.substring(12, 18)) ??
            // Keep the meaningful C1/C2/C3 bits editable when only their
            // inverted redundancy is damaged. Saving repairs all three bytes.
            MifareClassicDumpAnalyzer.accessConditionValues(
                trailer.substring(14, 18));
      }
      selections.add(values);
      dataPermissions.add(values == null
          ? null
          : List<List<int>>.generate(
              3,
              (block) => MifareClassicDumpAnalyzer.dataAccessPermissions(
                  values![block]),
            ));
      trailerPermissions.add(values == null
          ? null
          : MifareClassicDumpAnalyzer.trailerAccessPermissions(values[3]));
    }

    String permissionLabel(int permission) => switch (permission) {
          1 => 'A',
          2 => 'B',
          3 => 'A/B',
          _ => '-',
        };
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(localizations.access_conditions),
          content: SizedBox(
            width: 600,
            height: 520,
            child: Column(
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: selections.length,
                    itemBuilder: (context, sector) {
                      List<int>? values = selections[sector];
                      List<List<int>>? blocks = dataPermissions[sector];
                      List<List<int>>? trailer = trailerPermissions[sector];
                      if (values == null || blocks == null || trailer == null) {
                        return ListTile(
                          title: Text('${localizations.sector} $sector'),
                          subtitle: Text(
                              localizations.failed_to_decode_access_conditions),
                        );
                      }

                      Widget permissionDropdown(
                        String label,
                        int permission,
                        ValueChanged<int?> onChanged,
                      ) {
                        return SizedBox(
                          width: 112,
                          child: DropdownButtonFormField<int>(
                            initialValue: permission,
                            decoration: InputDecoration(
                              labelText: label,
                              isDense: true,
                            ),
                            items: [1, 2, 3, 0]
                                .map((value) => DropdownMenuItem<int>(
                                      value: value,
                                      child: Text(permissionLabel(value)),
                                    ))
                                .toList(),
                            onChanged: onChanged,
                          ),
                        );
                      }

                      List<Widget> blockEditors = List.generate(3, (block) {
                        String label = sector >= 32
                            ? '${localizations.block} '
                                '${block * 5}-${block * 5 + 4}'
                            : '${localizations.block} $block';
                        List<String> actions = [
                          localizations.read,
                          localizations.write,
                          localizations.inc,
                          localizations.dec,
                        ];
                        return SizedBox(
                          width: double.infinity,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: List.generate(4, (action) {
                                      return permissionDropdown(
                                        actions[action],
                                        blocks[block][action],
                                        (permission) {
                                          if (permission == null) return;
                                          setDialogState(() {
                                            blocks[block][action] = permission;
                                            error = null;
                                          });
                                        },
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      });

                      List<String> trailerParts = [
                        '${localizations.key} A',
                        localizations.acl,
                        '${localizations.key} B',
                      ];
                      blockEditors.add(SizedBox(
                        width: double.infinity,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(localizations.sector_trailer,
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 8),
                                ...List.generate(
                                    3,
                                    (part) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 6),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                  width: 80,
                                                  child:
                                                      Text(trailerParts[part])),
                                              Expanded(
                                                child: permissionDropdown(
                                                  localizations.read,
                                                  trailer[part][0],
                                                  (permission) {
                                                    if (permission == null) {
                                                      return;
                                                    }
                                                    setDialogState(() {
                                                      trailer[part][0] =
                                                          permission;
                                                      error = null;
                                                    });
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: permissionDropdown(
                                                  localizations.write,
                                                  trailer[part][1],
                                                  (permission) {
                                                    if (permission == null) {
                                                      return;
                                                    }
                                                    setDialogState(() {
                                                      trailer[part][1] =
                                                          permission;
                                                      error = null;
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                              ],
                            ),
                          ),
                        ),
                      ));

                      return ExpansionTile(
                        title: Text('${localizations.sector} $sector'),
                        children: blockEditors,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () {
                List<List<int>?> validatedSelections = [];
                for (int sector = 0; sector < selections.length; sector++) {
                  List<int>? values = selections[sector];
                  List<List<int>>? blocks = dataPermissions[sector];
                  List<List<int>>? trailer = trailerPermissions[sector];
                  if (values == null || blocks == null || trailer == null) {
                    validatedSelections.add(null);
                    continue;
                  }

                  List<int> validated = List<int>.from(values);
                  for (int block = 0; block < 3; block++) {
                    int? condition = MifareClassicDumpAnalyzer
                        .dataAccessConditionForPermissions(blocks[block]);
                    if (condition == null) {
                      setDialogState(() => error =
                          '${localizations.invalid_data_in_sector} $sector, '
                              '${localizations.block} $block');
                      return;
                    }
                    validated[block] = condition;
                  }

                  int? trailerCondition = MifareClassicDumpAnalyzer
                      .trailerAccessConditionForPermissions(
                    trailer,
                    preferredCondition: values[3],
                  );
                  if (trailerCondition == null) {
                    setDialogState(() => error =
                        '${localizations.invalid_data_in_sector} $sector, '
                            '${localizations.sector_trailer}');
                    return;
                  }
                  validated[3] = trailerCondition;
                  validatedSelections.add(validated);
                }

                for (int sector = 0;
                    sector < validatedSelections.length;
                    sector++) {
                  List<int>? values = validatedSelections[sector];
                  if (values == null) continue;
                  List<String> lines = controllers[sector].text.split('\n');
                  String trailer = lines.last.replaceAll(' ', '').trim();
                  String access =
                      MifareClassicDumpAnalyzer.encodeAccessConditions(values);
                  _replaceBlockHex(
                      sector,
                      lines.length - 1,
                      trailer.substring(0, 12) +
                          access +
                          trailer.substring(18));
                }
                Navigator.pop(dialogContext);
              },
              child: Text(localizations.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showValueBlocks() async {
    if (isUltralight) return;
    var localizations = AppLocalizations.of(context)!;
    List<int> sectorIndexes = [];
    List<int> lineIndexes = [];
    List<int> absoluteBlockIndexes = [];
    List<TextEditingController> valueControllers = [];
    List<TextEditingController> addressControllers = [];

    for (int sector = 0; sector < controllers.length; sector++) {
      List<String> lines = controllers[sector].text.split('\n');
      for (int block = 0; block < lines.length; block++) {
        String hexData = lines[block].replaceAll(' ', '').trim();
        int? value = MifareClassicDumpAnalyzer.valueBlockToInt(hexData);
        int? address = MifareClassicDumpAnalyzer.valueBlockAddress(hexData);
        if (value == null || address == null) continue;
        sectorIndexes.add(sector);
        lineIndexes.add(block);
        absoluteBlockIndexes
            .add(mfClassicGetFirstBlockCountBySector(sector) + block);
        valueControllers.add(TextEditingController(text: value.toString()));
        addressControllers.add(TextEditingController(text: address.toString()));
      }
    }

    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(localizations.value_blocks),
          content: SizedBox(
            width: 420,
            height: 360,
            child: valueControllers.isEmpty
                ? Center(child: Text(localizations.no_value_blocks_found))
                : Column(
                    children: [
                      if (error != null)
                        Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      Expanded(
                        child: ListView.separated(
                          itemCount: valueControllers.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) => Row(
                            children: [
                              SizedBox(
                                width: 72,
                                child: Text(
                                    '${localizations.block} ${absoluteBlockIndexes[index]}'),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: valueControllers[index],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          signed: true),
                                  decoration: InputDecoration(
                                      labelText: localizations.value),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: addressControllers[index],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Address'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
            if (valueControllers.isNotEmpty)
              TextButton(
                onPressed: () {
                  List<int> values = [];
                  List<int> addresses = [];
                  for (int i = 0; i < valueControllers.length; i++) {
                    int? value = int.tryParse(valueControllers[i].text);
                    int? address = int.tryParse(addressControllers[i].text);
                    if (value == null ||
                        value < -0x80000000 ||
                        value > 0x7FFFFFFF ||
                        address == null ||
                        address < 0 ||
                        address > 255) {
                      setDialogState(() => error =
                          '${localizations.invalid_data_in_block} ${absoluteBlockIndexes[i]}');
                      return;
                    }
                    values.add(value);
                    addresses.add(address);
                  }
                  for (int i = 0; i < values.length; i++) {
                    _replaceBlockHex(
                      sectorIndexes[i],
                      lineIndexes[i],
                      MifareClassicDumpAnalyzer.intToValueBlock(
                          values[i], addresses[i]),
                    );
                  }
                  Navigator.pop(dialogContext);
                },
                child: Text(localizations.save),
              ),
          ],
        ),
      ),
    );
    for (final controller in [...valueControllers, ...addressControllers]) {
      controller.dispose();
    }
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

  Color _getDiffColor() {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.red.shade300
        : Colors.red.shade700;
  }

  int _blockIndexFor(int controllerIndex, int lineIndex) {
    return isUltralight
        ? lineIndex
        : mfClassicGetFirstBlockCountBySector(controllerIndex) + lineIndex;
  }

  Uint8List? _compareBytesFor(int controllerIndex, int lineIndex) {
    if (compareData == null) return null;
    int blockIndex = _blockIndexFor(controllerIndex, lineIndex);
    if (blockIndex < 0 ||
        blockIndex >= compareData!.length ||
        compareData![blockIndex].isEmpty) {
      return null;
    }
    return compareData![blockIndex];
  }

  String _byteAt(String cleanHex, int byteIndex) {
    int start = byteIndex * 2;
    if (start + 2 <= cleanHex.length) {
      return cleanHex.substring(start, start + 2);
    }
    if (start < cleanHex.length) {
      return cleanHex.substring(start);
    }
    return '';
  }

  String _spaceHex(String cleanHex) {
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < cleanHex.length; i += 2) {
      if (i > 0) buffer.write(' ');
      buffer.write(_byteAt(cleanHex, i ~/ 2));
    }
    return buffer.toString();
  }

  List<TextSpan> _byteSpans(
      String cleanHex, List<bool> byteDiff, int byteCount) {
    Color normalColor = _getDefaultHighlightColor();
    Color diffColor = _getDiffColor();

    List<TextSpan> spans = [];
    for (int k = 0; k < byteCount; k++) {
      if (k > 0) spans.add(const TextSpan(text: ' '));
      String token = _byteAt(cleanHex, k);
      if (token.isEmpty) token = '--';
      bool differs = k < byteDiff.length ? byteDiff[k] : true;
      spans.add(TextSpan(
        text: token,
        style: differs
            ? TextStyle(color: diffColor, fontWeight: FontWeight.bold)
            : TextStyle(color: normalColor),
      ));
    }
    return spans;
  }

  Future<void> _startCompare() async {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    List<CardSave> candidates = appState.sharedPreferencesProvider
        .getCards()
        .where((card) =>
            card.id != widget.cardSave.id && card.tag == widget.cardSave.tag)
        .toList();

    if (candidates.isEmpty) {
      _showErrorDialog(localizations.no_dumps_to_compare);
      return;
    }

    CardSave? selected = await showDialog<CardSave>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.select_dump_to_compare),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              CardSave card = candidates[index];
              return ListTile(
                leading: Icon(Icons.credit_card, color: card.color),
                title: Text(card.name.isEmpty ? "⠀" : card.name),
                subtitle: Text(card.uid),
                onTap: () => Navigator.pop(context, card),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
        ],
      ),
    );

    if (selected != null) {
      setState(() {
        compareData =
            selected.data.map((bytes) => Uint8List.fromList(bytes)).toList();
        compareName = selected.name;
        isCompareMode = true;
      });
    }
  }

  void _exitCompare() {
    setState(() {
      isCompareMode = false;
      compareData = null;
      compareName = '';
    });
  }

  Widget _buildAdaptiveEditor(int controllerIndex) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double optimalFontSize =
            _guessOptimalFontSize(controllerIndex, constraints);
        if (isCompareMode) {
          return _buildCompareView(controllerIndex, fontSize: optimalFontSize);
        }
        return _buildOriginalEditor(controllerIndex, fontSize: optimalFontSize);
      },
    );
  }

  double _guessOptimalFontSize(
      int controllerIndex, BoxConstraints constraints) {
    String sampleText = _getLongestLine(controllerIndex);

    for (double fontSize = 16.0; fontSize >= 10.0; fontSize -= 0.1) {
      if (_doesTextFitOnOneLine(sampleText, fontSize,
          constraints.maxWidth - _calculateLeftPadding(context, fontSize))) {
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

  Widget _buildCompareView(int controllerIndex, {double fontSize = 14.0}) {
    List<String> lines = controllers[controllerIndex].text.split('\n');
    List<TextSpan> spans = [];

    Color blockNumberColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    Color labelColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade300
        : Colors.grey.shade700;
    Color defaultColor = _getDefaultHighlightColor();

    String currentName =
        widget.cardSave.name.isEmpty ? '⠀' : widget.cardSave.name;
    String otherName = compareName.isEmpty ? '⠀' : compareName;

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      int blockNumber = _blockIndexFor(controllerIndex, i);
      String numStr = blockNumber.toString().padLeft(3, ' ');

      String currentClean = line.replaceAll(' ', '').toUpperCase();
      Uint8List? otherBytes = _compareBytesFor(controllerIndex, i);
      String otherClean =
          otherBytes != null ? bytesToHex(otherBytes).toUpperCase() : '';

      int byteCount = (currentClean.length + 1) ~/ 2;
      List<bool> byteDiff = [];
      bool blockDiffers = false;
      for (int k = 0; k < byteCount; k++) {
        bool differs = otherClean.isEmpty ||
            _byteAt(currentClean, k) != _byteAt(otherClean, k);
        byteDiff.add(differs);
        if (differs) blockDiffers = true;
      }

      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '\n'));
      }

      if (!blockDiffers) {
        // Identical block: compact single line.
        spans.add(TextSpan(
          text: '$numStr: ',
          style: TextStyle(color: blockNumberColor),
        ));
        spans.add(TextSpan(
          text: _spaceHex(currentClean),
          style: TextStyle(color: defaultColor),
        ));
        continue;
      }

      // Differing block: each dump's row is preceded by its card name so it is
      // clear which card the row belongs to. Changed bytes are highlighted.
      String gutter = ' ' * (numStr.length + 2);

      spans.add(TextSpan(
        text: '$gutter$currentName',
        style: TextStyle(color: labelColor, fontWeight: FontWeight.bold),
      ));
      spans.add(const TextSpan(text: '\n'));
      spans.add(TextSpan(
        text: '$numStr: ',
        style: TextStyle(color: blockNumberColor),
      ));
      spans.addAll(_byteSpans(currentClean, byteDiff, byteCount));

      spans.add(const TextSpan(text: '\n'));
      spans.add(TextSpan(
        text: '$gutter$otherName',
        style: TextStyle(color: labelColor, fontWeight: FontWeight.bold),
      ));
      spans.add(const TextSpan(text: '\n'));
      spans.add(TextSpan(
        text: '$numStr: ',
        style: TextStyle(color: blockNumberColor),
      ));
      spans.addAll(_byteSpans(otherClean, byteDiff, byteCount));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SelectableText.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: fontSize,
            height: 1.4,
            letterSpacing: 0.0,
          ),
          children: spans,
        ),
      ),
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

    if (isCompareMode) {
      return _buildCompareLegend();
    }

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

  Widget _buildCompareLegend() {
    var localizations = AppLocalizations.of(context)!;
    Color textColor = _getDefaultHighlightColor();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.comparison,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: _getDiffColor(),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localizations.difference,
                  style: TextStyle(color: textColor),
                ),
              ),
            ],
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
            if (!isCompareMode)
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
            SafeArea(
              child: Container(
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
                    if (isCompareMode)
                      ElevatedButton.icon(
                        onPressed: _exitCompare,
                        label: Text(localizations.exit_comparison),
                      )
                    else ...[
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
                      ElevatedButton.icon(
                        onPressed: _startCompare,
                        label: Text(localizations.compare),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
