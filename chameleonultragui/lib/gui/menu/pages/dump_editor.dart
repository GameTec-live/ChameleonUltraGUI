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

part 'dump_editor_input.dart';
part 'dump_editor_actions.dart';
part 'dump_editor_highlighting.dart';
part 'dump_editor_view.dart';

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

  void updateEditorState(VoidCallback update) => setState(update);

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
