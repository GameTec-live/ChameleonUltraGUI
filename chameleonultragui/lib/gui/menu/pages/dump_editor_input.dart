part of 'dump_editor.dart';

// Keeps hex editing and cursor behavior isolated from page layout.
extension on DumpEditorState {
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
}
