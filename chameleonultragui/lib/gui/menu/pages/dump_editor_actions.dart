part of 'dump_editor.dart';

// Keeps validation, persistence, and editor dialogs isolated from rendering.
extension on DumpEditorState {
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
    updateEditorState(() {
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
        if (sectorTrailer.length >= 18) {
          String accessConditions = sectorTrailer.substring(14, 18);
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
}
