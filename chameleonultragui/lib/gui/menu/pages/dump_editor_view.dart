part of 'dump_editor.dart';

// Keeps editor and legend widgets isolated from state orchestration.
extension on DumpEditorState {
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
                      updateEditorState(() {
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
}
