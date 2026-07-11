part of 'dump_editor.dart';

// Keeps dump comparison and byte highlighting isolated from page layout.
extension on DumpEditorState {
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
      updateEditorState(() {
        compareData =
            selected.data.map((bytes) => Uint8List.fromList(bytes)).toList();
        compareName = selected.name;
        isCompareMode = true;
      });
    }
  }

  void _exitCompare() {
    updateEditorState(() {
      isCompareMode = false;
      compareData = null;
      compareName = '';
    });
  }
}
