import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_highlighter.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_analyzer.dart';
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
  late List<TextEditingController> sectorControllers;
  late List<String>
      initialSectorTexts; // Store initial text content for change tracking
  bool hasUnsavedChanges = false;
  bool isInsertMode = false;
  ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    initEditor();
  }

  @override
  void dispose() {
    for (var controller in sectorControllers) {
      controller.dispose();
    }
    scrollController.dispose();
    super.dispose();
  }

  void initEditor() {
    // Create a deep copy of the dump data to avoid modifying the original
    dumpData =
        widget.cardSave.data.map((bytes) => Uint8List.fromList(bytes)).toList();

    // Initialize controllers for each sector
    sectorControllers = [];
    initialSectorTexts = []; // Initialize the initial text storage
    MifareClassicType cardType =
        chameleonTagTypeGetMfClassicType(widget.cardSave.tag);
    int sectorCount = mfClassicGetSectorCount(cardType);

    for (int sector = 0; sector < sectorCount; sector++) {
      int blocksPerSector = mfClassicGetBlockCountBySector(sector);
      int firstBlock = mfClassicGetFirstBlockCountBySector(sector);

      // Build sector data text with spaces between bytes
      String sectorText = '';
      for (int block = 0; block < blocksPerSector; block++) {
        int blockIndex = firstBlock + block;
        if (blockIndex < dumpData.length && dumpData[blockIndex].isNotEmpty) {
          if (block > 0) sectorText += '\n';
          String hexData = bytesToHex(dumpData[blockIndex]).toUpperCase();
          // Add space after every 2 hex characters (1 byte)
          String spacedHex = '';
          for (int i = 0; i < hexData.length; i += 2) {
            if (i > 0) spacedHex += ' ';
            spacedHex += hexData.substring(i, i + 2);
          }
          sectorText += spacedHex;
        }
      }

      TextEditingController controller =
          TextEditingController(text: sectorText);
      controller.addListener(() => _onSectorDataChanged(sector));
      sectorControllers.add(controller);
      initialSectorTexts.add(sectorText); // Store initial text content
    }
  }

  void _onSectorDataChanged(int sector) {
    // Only mark as changed if the actual text content has changed
    if (sector < sectorControllers.length &&
        sector < initialSectorTexts.length) {
      String currentText = sectorControllers[sector].text;
      String initialText = initialSectorTexts[sector];

      if (currentText != initialText) {
        setState(() {
          hasUnsavedChanges = true;
        });
      }
    }
  }

  TextEditingValue _handleInsertMode(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // In insert mode, characters are inserted and existing text shifts right
    // But we need to respect the 32-character limit per line

    if (newValue.text.length <= oldValue.text.length) {
      // Not an insertion (deletion or same), handle as normal
      return _processTextWithSpacing(newValue, false);
    }

    // Process each line separately to handle insert mode correctly
    List<String> oldLines = oldValue.text.split('\n');
    List<String> newLines = newValue.text.split('\n');
    List<String> processedLines = [];

    // Calculate cursor position
    int oldCursorPos = newValue.selection.baseOffset;
    int newCursorPos = oldCursorPos;
    int currentPos = 0;
    int processedPos = 0;

    for (int lineIndex = 0; lineIndex < newLines.length; lineIndex++) {
      String newLine = newLines[lineIndex];
      String oldLine = lineIndex < oldLines.length ? oldLines[lineIndex] : '';

      // Clean both lines (remove spaces)
      String cleanNewLine = newLine.replaceAll(' ', '');
      String cleanOldLine = oldLine.replaceAll(' ', '');

      // If this line got longer, we need to handle insert mode
      if (cleanNewLine.length > cleanOldLine.length) {
        // Limit to 32 characters - if insert would exceed, truncate from the end
        if (cleanNewLine.length > 32) {
          cleanNewLine = cleanNewLine.substring(0, 32);
        }
      } else {
        // Normal case, just limit to 32
        if (cleanNewLine.length > 32) {
          cleanNewLine = cleanNewLine.substring(0, 32);
        }
      }

      // Add spaces back between bytes
      String spacedLine = '';
      for (int i = 0; i < cleanNewLine.length; i += 2) {
        if (i > 0) spacedLine += ' ';
        spacedLine += cleanNewLine.substring(i, i + 2);
      }
      processedLines.add(spacedLine);

      // Calculate cursor position for this line
      int lineStartPos = currentPos;
      int lineEndPos = currentPos + newLine.length;
      int processedLineStartPos = processedPos;
      int processedLineEndPos = processedPos + spacedLine.length;

      if (oldCursorPos >= lineStartPos && oldCursorPos <= lineEndPos) {
        // Cursor is in this line, calculate relative position
        int relativePos = oldCursorPos - lineStartPos;
        int cleanRelativePos = 0;
        int originalIndex = 0;

        // Map cursor position from original line to clean line
        for (int i = 0;
            i < newLine.length && originalIndex < relativePos;
            i++) {
          if (newLine[i] != ' ') {
            cleanRelativePos++;
          }
          originalIndex++;
        }

        // Map clean position to spaced position
        int spacedRelativePos = 0;
        for (int i = 0; i < cleanRelativePos; i++) {
          if (i > 0 && i % 2 == 0) {
            spacedRelativePos++; // Add space
          }
          spacedRelativePos++;
        }

        newCursorPos = processedLineStartPos +
            spacedRelativePos.clamp(0, spacedLine.length);
      }

      currentPos = lineEndPos + 1; // +1 for newline
      processedPos = processedLineEndPos + 1; // +1 for newline
    }

    String processedText = processedLines.join('\n').toUpperCase();

    return TextEditingValue(
      text: processedText,
      selection: TextSelection.collapsed(
        offset: newCursorPos.clamp(0, processedText.length),
      ),
    );
  }

  TextEditingValue _handleOverwriteMode(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // In overwrite mode, just process the text normally - no insertion detection
    // Characters replace existing ones at cursor position
    return _processTextWithSpacing(newValue, false);
  }

  TextEditingValue _processTextWithSpacing(
      TextEditingValue value, bool allowLongerLines) {
    List<String> lines = value.text.split('\n');
    List<String> processedLines = [];

    // Calculate cursor position mapping
    int oldCursorPos = value.selection.baseOffset;
    int newCursorPos = oldCursorPos;
    int currentPos = 0;
    int processedPos = 0;

    for (String line in lines) {
      String cleanLine = line.replaceAll(' ', '');

      // Apply length limits
      if (allowLongerLines) {
        // In insert mode, allow temporary expansion but cap at reasonable limit
        if (cleanLine.length > 48) {
          cleanLine = cleanLine.substring(0, 48);
        }
      } else {
        // In overwrite mode, strict 32 character limit
        if (cleanLine.length > 32) {
          cleanLine = cleanLine.substring(0, 32);
        }
      }

      // Add spaces back between bytes
      String spacedLine = '';
      for (int i = 0; i < cleanLine.length; i += 2) {
        if (i > 0) spacedLine += ' ';
        spacedLine += cleanLine.substring(i, i + 2);
      }
      processedLines.add(spacedLine);

      // Calculate new cursor position
      int lineStartPos = currentPos;
      int lineEndPos = currentPos + line.length;
      int processedLineStartPos = processedPos;
      int processedLineEndPos = processedPos + spacedLine.length;

      if (oldCursorPos >= lineStartPos && oldCursorPos <= lineEndPos) {
        // Cursor is in this line, calculate relative position
        int relativePos = oldCursorPos - lineStartPos;
        int cleanRelativePos = 0;
        int originalIndex = 0;

        // Map cursor position from original line to clean line
        for (int i = 0; i < line.length && originalIndex < relativePos; i++) {
          if (line[i] != ' ') {
            cleanRelativePos++;
          }
          originalIndex++;
        }

        // Map clean position to spaced position
        int spacedRelativePos = 0;
        for (int i = 0; i < cleanRelativePos; i++) {
          if (i > 0 && i % 2 == 0) {
            spacedRelativePos++; // Add space
          }
          spacedRelativePos++;
        }

        newCursorPos = processedLineStartPos +
            spacedRelativePos.clamp(0, spacedLine.length);
      }

      currentPos = lineEndPos + 1; // +1 for newline
      processedPos = processedLineEndPos + 1; // +1 for newline
    }

    String processedText = processedLines.join('\n').toUpperCase();

    return TextEditingValue(
      text: processedText,
      selection: TextSelection.collapsed(
        offset: newCursorPos.clamp(0, processedText.length),
      ),
    );
  }

  bool _validateSectorDataForSave(String sectorData) {
    List<String> lines = sectorData.split('\n');
    int sector = sectorControllers.indexOf(sectorControllers.firstWhere(
      (controller) => controller.text == sectorData,
      orElse: () => sectorControllers[0],
    ));

    int expectedBlocks = mfClassicGetBlockCountBySector(sector);

    if (lines.length != expectedBlocks) {
      return false;
    }

    for (String line in lines) {
      // Remove spaces and check if line is valid hex and exactly 32 characters (16 bytes)
      String cleanLine = line.replaceAll(' ', '').trim();
      if (!RegExp(r'^[0-9A-Fa-f-]{32}$').hasMatch(cleanLine)) {
        return false;
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

    // Validate and save the dump
    List<Uint8List> updatedDump = List.from(dumpData);

    for (int sector = 0; sector < sectorControllers.length; sector++) {
      if (!_validateSectorDataForSave(sectorControllers[sector].text)) {
        _showErrorDialog('${localizations.invalid_data_in_sector} $sector');
        return;
      }

      List<String> lines = sectorControllers[sector].text.split('\n');
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
    }

    // Call the save callback
    widget.onSave(updatedDump);

    // Update initial text content after successful save
    for (int sector = 0; sector < sectorControllers.length; sector++) {
      if (sector < initialSectorTexts.length) {
        initialSectorTexts[sector] = sectorControllers[sector].text;
      }
    }

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
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close editor
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

    // Convert current dump data to ASCII
    List<String> asciiData = [];
    for (int sector = 0; sector < sectorControllers.length; sector++) {
      List<String> lines = sectorControllers[sector].text.split('\n');
      asciiData.add('${localizations.sector}: $sector');
      for (int block = 0; block < lines.length; block++) {
        String hexData = lines[block].replaceAll(' ', '').trim();
        if (hexData.isNotEmpty) {
          String ascii = DumpAnalyzer.hexToAscii(hexData);
          asciiData.add('${localizations.block} $block: $ascii');
        }
      }
      asciiData.add('');
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
              style: const TextStyle(fontFamily: 'monospace'),
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
    var localizations = AppLocalizations.of(context)!;

    List<String> acData = [];
    for (int sector = 0; sector < sectorControllers.length; sector++) {
      List<String> lines = sectorControllers[sector].text.split('\n');
      if (lines.isNotEmpty) {
        // Get the sector trailer (last line)
        String sectorTrailer = lines.last.replaceAll(' ', '').trim();
        if (sectorTrailer.length >= 20) {
          String accessConditions = sectorTrailer.substring(12, 20);
          Map<String, dynamic> decoded =
              DumpAnalyzer.decodeAccessConditions(accessConditions, context);

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
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
    var localizations = AppLocalizations.of(context)!;

    List<String> valueData = [];
    bool foundValueBlocks = false;

    for (int sector = 0; sector < sectorControllers.length; sector++) {
      List<String> lines = sectorControllers[sector].text.split('\n');
      for (int block = 0; block < lines.length; block++) {
        String hexData = lines[block].replaceAll(' ', '').trim();
        if (hexData.isNotEmpty) {
          int? value = DumpAnalyzer.valueBlockToInt(hexData);
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
              style: const TextStyle(fontFamily: 'monospace'),
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

  List<TextSpan> _buildHighlightedTextWithBlockNumbers(int sector) {
    List<String> lines = sectorControllers[sector].text.split('\n');
    List<TextSpan> spans = [];

    int firstBlock = mfClassicGetFirstBlockCountBySector(sector);

    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      String line = lines[lineIndex].trim();

      // Add newline if not the first line
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '\n'));
      }

      // Calculate block number
      int blockNumber = firstBlock + lineIndex;

      // Add block number with consistent padding (spaces instead of zeros)
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

      // Handle empty lines
      if (line.isEmpty) {
        spans.add(TextSpan(
          text: '',
          style: TextStyle(color: DumpHighlighter.getDefaultColor(context)),
        ));
        continue;
      }

      // Get highlighted spans for this line
      List<TextSpan> lineSpans =
          _getHighlightedLineSpans(line, sector, lineIndex, context);

      // Add the highlighted line content
      spans.addAll(lineSpans);
    }

    return spans;
  }

  List<TextSpan> _getHighlightedLineSpans(
      String line, int sector, int lineIndex, BuildContext context) {
    if (line.isEmpty) {
      return [
        TextSpan(
          text: '',
          style: TextStyle(color: DumpHighlighter.getDefaultColor(context)),
        )
      ];
    }

    // Get the number of blocks per sector to determine if this is the last block (sector trailer)
    int blocksPerSector = mfClassicGetBlockCountBySector(sector);
    bool isSectorTrailer = lineIndex == blocksPerSector - 1;

    // Check if this is the first block of sector 0 (contains UID)
    bool isFirstBlock = sector == 0 && lineIndex == 0;

    if (isSectorTrailer) {
      return DumpHighlighter.highlightSectorTrailer(line, context);
    } else if (isFirstBlock) {
      return DumpHighlighter.highlightFirstBlock(line, context);
    } else {
      return DumpHighlighter.highlightDataBlock(line, context);
    }
  }

  Widget _buildSectorEditor(int sector) {
    var localizations = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sector header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            '${localizations.sector}: $sector',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).primaryColor,
            ),
          ),
        ),

        // Sector data editor with highlighting
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
          child: Stack(
            children: [
              // Highlighted text overlay
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: IgnorePointer(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          height: 1.2,
                          letterSpacing: 0.0,
                        ),
                        children: _buildHighlightedTextWithBlockNumbers(sector),
                      ),
                    ),
                  ),
                ),
              ),
              // Transparent text field for input
              TextFormField(
                controller: sectorControllers[sector],
                maxLines: null,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: Colors.transparent,
                  height: 1.2,
                  letterSpacing: 0.0,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(47, 12, 12, 12),
                  hintText: '',
                  isDense: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9A-Fa-f\n\s-]')),
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (isInsertMode) {
                      // Insert mode: insert character and shift remaining characters
                      return _handleInsertMode(oldValue, newValue);
                    } else {
                      // Overwrite mode: replace characters at cursor position
                      return _handleOverwriteMode(oldValue, newValue);
                    }
                  }),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildColorLegend() {
    var localizations = AppLocalizations.of(context)!;

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
                  color: DumpHighlighter.getDefaultColor(context),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${localizations.insert_mode}: ',
                    style: TextStyle(
                      color: DumpHighlighter.getDefaultColor(context),
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
            children: [
              _buildLegendItem(
                  localizations.uid, DumpHighlighter.getUidColor(context)),
              _buildLegendItem(localizations.value_block,
                  DumpHighlighter.getValueBlockColor(context)),
              _buildLegendItem(
                  localizations.key_a, DumpHighlighter.getKeyAColor(context)),
              _buildLegendItem(
                  localizations.key_b, DumpHighlighter.getKeyBColor(context)),
              _buildLegendItem(localizations.access_conditions,
                  DumpHighlighter.getAccessConditionsColor(context)),
              _buildLegendItem(
                  localizations.block_index,
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600),
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
          style: TextStyle(color: DumpHighlighter.getDefaultColor(context)),
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
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // Color legend
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 395),
                      child: _buildColorLegend(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Sector editors
                  ...List.generate(
                    sectorControllers.length,
                    (index) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 395),
                        child: _buildSectorEditor(index),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Fixed bottom toolbar
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
                  ElevatedButton(
                    onPressed: _showAccessConditions,
                    child: Text(localizations.ac),
                  ),
                  ElevatedButton(
                    onPressed: _showValueBlocks,
                    child: Text(localizations.value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
