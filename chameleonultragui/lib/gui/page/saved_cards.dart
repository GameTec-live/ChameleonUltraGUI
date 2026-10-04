import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:chameleonultragui/gui/component/element_button.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/view.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/view.dart';
import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' show basename;
import 'package:provider/provider.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/create.dart';
import 'package:chameleonultragui/gui/menu/dialogs/confirm_delete.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class SavedCardsPage extends StatefulWidget {
  const SavedCardsPage({super.key});

  @override
  SavedCardsPageState createState() => SavedCardsPageState();
}

class SavedCardsPageState extends State<SavedCardsPage> {
  TagType selectedType = TagType.unknown;
  String? currentFolderId;
  String? currentDictionaryFolderId;

  Future<void> _createCard() async {
    await showDialog(
      context: context,
      builder: (context) => CardCreateMenu(folderId: currentFolderId),
    );
  }

  Widget _createMenuButton(
    ChameleonGUIState appState, {
    required bool elevated,
  }) {
    final localizations = AppLocalizations.of(context)!;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.credit_card),
          onPressed: _createCard,
          child: Text(localizations.card),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.create_new_folder),
          onPressed: _editFolder,
          child: Text(localizations.folder),
        ),
      ],
      builder: (context, controller, child) {
        void toggleMenu() {
          controller.isOpen ? controller.close() : controller.open();
        }

        if (elevated) {
          return ElevatedButton(
            onPressed: toggleMenu,
            style: customCardButtonStyle(appState),
            child: const Icon(Icons.add),
          );
        }
        return IconButton(
          onPressed: toggleMenu,
          tooltip: localizations.create,
          icon: const Icon(Icons.add),
        );
      },
    );
  }

  Future<void> _editFolder([CardFolder? folder]) async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final name = TextEditingController(text: folder?.name ?? '');
    var color = folder?.color ?? Colors.deepOrange;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(folder == null
              ? localizations.create_folder
              : localizations.edit_folder),
          content: TextField(
            controller: name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: localizations.name,
              prefixIcon: IconButton(
                icon: Icon(Icons.folder, color: color),
                tooltip: localizations.pick_color,
                onPressed: () async {
                  var picked = color;
                  final accepted = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(localizations.folder_color),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          pickerColor: picked,
                          onColorChanged: (value) => picked = value,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(localizations.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(localizations.ok),
                        ),
                      ],
                    ),
                  );
                  if (accepted == true) {
                    setDialogState(() => color = picked);
                  }
                },
              ),
            ),
            onSubmitted: (_) => Navigator.pop(
              dialogContext,
              name.text.trim().isNotEmpty,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                name.text.trim().isNotEmpty,
              ),
              child: Text(
                  folder == null ? localizations.create : localizations.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final folders = appState.sharedPreferencesProvider.getCardFolders();
    if (folder == null) {
      folders.add(CardFolder(
        name: name.text.trim(),
        color: color,
        parentId: currentFolderId,
      ));
    } else {
      final index = folders.indexWhere((item) => item.id == folder.id);
      if (index >= 0) {
        folders[index].name = name.text.trim();
        folders[index].color = color;
      }
    }
    appState.sharedPreferencesProvider.setCardFolders(folders);
    appState.changesMade();
  }

  Set<String> _folderTreeIds(String rootId, List<CardFolder> folders) {
    final result = <String>{rootId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in folders) {
        if (folder.parentId != null &&
            result.contains(folder.parentId) &&
            result.add(folder.id)) {
          changed = true;
        }
      }
    }
    return result;
  }

  Future<String?> _pickFolderDestination({CardFolder? movingFolder}) async {
    final localizations = AppLocalizations.of(context)!;
    final folders = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getCardFolders();
    final excluded = movingFolder == null
        ? <String>{}
        : _folderTreeIds(movingFolder.id, folders);
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(localizations.move_to_folder),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__root__'),
            child: ListTile(
              leading: const Icon(Icons.home),
              title: Text(localizations.saved_cards),
            ),
          ),
          ...folders.where((folder) => !excluded.contains(folder.id)).map(
                (folder) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, folder.id),
                  child: ListTile(
                    leading: Icon(Icons.folder, color: folder.color),
                    title: Text(folder.name),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _moveCard(CardSave card) async {
    final destination = await _pickFolderDestination();
    if (destination == null) return;
    if (!mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final cards = appState.sharedPreferencesProvider.getCards();
    final index = cards.indexWhere((item) => item.id == card.id);
    if (index >= 0) {
      cards[index].folderId = destination == '__root__' ? null : destination;
    }
    appState.sharedPreferencesProvider.setCards(cards);
    appState.changesMade();
  }

  Future<void> _moveFolder(CardFolder folder) async {
    final destination = await _pickFolderDestination(movingFolder: folder);
    if (destination == null) return;
    if (!mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getCardFolders();
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (index >= 0) {
      folders[index].parentId = destination == '__root__' ? null : destination;
    }
    appState.sharedPreferencesProvider.setCardFolders(folders);
    appState.changesMade();
  }

  Future<void> _deleteFolder(CardFolder folder) async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.delete_folder_title(folder.name)),
        content: Text(localizations.delete_card_folder_confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localizations.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final folders = appState.sharedPreferencesProvider.getCardFolders();
    final ids = _folderTreeIds(folder.id, folders);
    final cards = appState.sharedPreferencesProvider
        .getCards()
        .where((card) => !ids.contains(card.folderId))
        .toList();
    appState.sharedPreferencesProvider.setCardFolders(
        folders.where((item) => !ids.contains(item.id)).toList());
    appState.sharedPreferencesProvider.setCards(cards);
    appState.changesMade();
  }

  Future<void> _exportFolder(CardFolder folder) async {
    final localizations = AppLocalizations.of(context)!;
    final provider =
        context.read<ChameleonGUIState>().sharedPreferencesProvider;
    final folders = provider.getCardFolders();
    final ids = _folderTreeIds(folder.id, folders);
    final bundle = CardFolderBundle(
      rootFolderId: folder.id,
      folders: folders.where((item) => ids.contains(item.id)).toList(),
      cards: provider
          .getCards()
          .where((card) => ids.contains(card.folderId))
          .toList(),
    );
    await FilePicker.saveFile(
      dialogTitle: localizations.export_folder,
      fileName: '${folder.name}.json',
      bytes: const Utf8Encoder().convert(bundle.toJson()),
    );
  }

  Future<void> _importFolderSource(String source) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final bundle = CardFolderBundle.fromJson(source);
      final appState = context.read<ChameleonGUIState>();
      final folders = appState.sharedPreferencesProvider.getCardFolders();
      final cards = appState.sharedPreferencesProvider.getCards();
      final idMap = <String, String>{};
      for (final imported in bundle.folders) {
        idMap[imported.id] = CardFolder(name: '').id;
      }
      for (final imported in bundle.folders) {
        folders.add(CardFolder(
          id: idMap[imported.id],
          name: imported.name,
          color: imported.color,
          parentId: imported.id == bundle.rootFolderId
              ? currentFolderId
              : idMap[imported.parentId],
        ));
      }
      for (final imported in bundle.cards) {
        final copy = CardSave.fromJson(imported.toJson());
        copy.id = CardFolder(name: '').id;
        copy.folderId = idMap[imported.folderId];
        cards.add(copy);
      }
      appState.sharedPreferencesProvider.setCardFolders(folders);
      appState.sharedPreferencesProvider.setCards(cards);
      appState.changesMade();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.invalid_folder_export)),
      );
    }
  }

  Set<String> _dictionaryFolderTreeIds(
      String rootId, List<DictionaryFolder> folders) {
    final result = <String>{rootId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in folders) {
        if (folder.parentId != null &&
            result.contains(folder.parentId) &&
            result.add(folder.id)) {
          changed = true;
        }
      }
    }
    return result;
  }

  Future<void> _editDictionaryFolder([DictionaryFolder? folder]) async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final name = TextEditingController(text: folder?.name ?? '');
    var color = folder?.color ?? Colors.deepOrange;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(folder == null
              ? localizations.create_folder
              : localizations.edit_folder),
          content: TextField(
            controller: name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: localizations.name,
              prefixIcon: IconButton(
                icon: Icon(Icons.folder, color: color),
                onPressed: () async {
                  var picked = color;
                  final accepted = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(localizations.folder_color),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          pickerColor: picked,
                          onColorChanged: (value) => picked = value,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(localizations.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(localizations.ok),
                        ),
                      ],
                    ),
                  );
                  if (accepted == true) {
                    setDialogState(() => color = picked);
                  }
                },
              ),
            ),
            onSubmitted: (_) => Navigator.pop(
              dialogContext,
              name.text.trim().isNotEmpty,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                name.text.trim().isNotEmpty,
              ),
              child: Text(
                  folder == null ? localizations.create : localizations.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
    if (folder == null) {
      folders.add(DictionaryFolder(
        name: name.text.trim(),
        color: color,
        parentId: currentDictionaryFolderId,
      ));
    } else {
      final index = folders.indexWhere((item) => item.id == folder.id);
      if (index >= 0) {
        folders[index].name = name.text.trim();
        folders[index].color = color;
      }
    }
    appState.sharedPreferencesProvider.setDictionaryFolders(folders);
    appState.changesMade();
  }

  Future<String?> _pickDictionaryFolderDestination(
      {DictionaryFolder? movingFolder}) {
    final localizations = AppLocalizations.of(context)!;
    final folders = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getDictionaryFolders();
    final excluded = movingFolder == null
        ? <String>{}
        : _dictionaryFolderTreeIds(movingFolder.id, folders);
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(localizations.move_to_folder),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__root__'),
            child: ListTile(
              leading: const Icon(Icons.home),
              title: Text(localizations.dictionaries),
            ),
          ),
          ...folders.where((folder) => !excluded.contains(folder.id)).map(
                (folder) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, folder.id),
                  child: ListTile(
                    leading: Icon(Icons.folder, color: folder.color),
                    title: Text(folder.name),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _moveDictionary(Dictionary dictionary) async {
    final destination = await _pickDictionaryFolderDestination();
    if (destination == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final dictionaries = appState.sharedPreferencesProvider.getDictionaries();
    final index = dictionaries.indexWhere((item) => item.id == dictionary.id);
    if (index >= 0) {
      dictionaries[index].folderId =
          destination == '__root__' ? null : destination;
    }
    appState.sharedPreferencesProvider.setDictionaries(dictionaries);
    appState.changesMade();
  }

  Future<void> _moveDictionaryFolder(DictionaryFolder folder) async {
    final destination =
        await _pickDictionaryFolderDestination(movingFolder: folder);
    if (destination == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (index >= 0) {
      folders[index].parentId = destination == '__root__' ? null : destination;
    }
    appState.sharedPreferencesProvider.setDictionaryFolders(folders);
    appState.changesMade();
  }

  Future<void> _deleteDictionaryFolder(DictionaryFolder folder) async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.delete_folder_title(folder.name)),
        content: Text(localizations.delete_dictionary_folder_confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localizations.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
    final ids = _dictionaryFolderTreeIds(folder.id, folders);
    appState.sharedPreferencesProvider.setDictionaryFolders(
      folders.where((item) => !ids.contains(item.id)).toList(),
    );
    appState.sharedPreferencesProvider.setDictionaries(
      appState.sharedPreferencesProvider
          .getDictionaries()
          .where((dictionary) => !ids.contains(dictionary.folderId))
          .toList(),
    );
    appState.changesMade();
  }

  Future<void> _exportDictionaryFolder(DictionaryFolder folder) async {
    final localizations = AppLocalizations.of(context)!;
    final provider =
        context.read<ChameleonGUIState>().sharedPreferencesProvider;
    final folders = provider.getDictionaryFolders();
    final ids = _dictionaryFolderTreeIds(folder.id, folders);
    final bundle = DictionaryFolderBundle(
      rootFolderId: folder.id,
      folders: folders.where((item) => ids.contains(item.id)).toList(),
      dictionaries: provider
          .getDictionaries()
          .where((dictionary) => ids.contains(dictionary.folderId))
          .toList(),
    );
    await FilePicker.saveFile(
      dialogTitle: localizations.export_dictionary_folder,
      fileName: '${folder.name}.json',
      bytes: const Utf8Encoder().convert(bundle.toJson()),
    );
  }

  Future<void> _importDictionaryFolderSource(String source) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final bundle = DictionaryFolderBundle.fromJson(source);
      final appState = context.read<ChameleonGUIState>();
      final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
      final dictionaries = appState.sharedPreferencesProvider.getDictionaries();
      final idMap = <String, String>{};
      for (final imported in bundle.folders) {
        idMap[imported.id] = DictionaryFolder(name: '').id;
      }
      for (final imported in bundle.folders) {
        folders.add(DictionaryFolder(
          id: idMap[imported.id],
          name: imported.name,
          color: imported.color,
          parentId: imported.id == bundle.rootFolderId
              ? currentDictionaryFolderId
              : idMap[imported.parentId],
        ));
      }
      for (final imported in bundle.dictionaries) {
        final copy = Dictionary.fromJson(imported.toJson());
        copy.id = DictionaryFolder(name: '').id;
        copy.folderId = idMap[imported.folderId];
        dictionaries.add(copy);
      }
      appState.sharedPreferencesProvider.setDictionaryFolders(folders);
      appState.sharedPreferencesProvider.setDictionaries(dictionaries);
      appState.changesMade();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.invalid_dictionary_folder_export)),
      );
    }
  }

  Future<void> _createDictionary() async {
    await showDialog(
      context: context,
      builder: (context) => DictionaryEditMenu(
        dictionary: Dictionary(
          name: '',
          folderId: currentDictionaryFolderId,
        ),
        isNew: true,
      ),
    );
  }

  Widget _dictionaryCreateMenuButton(
    ChameleonGUIState appState, {
    required bool elevated,
  }) {
    final localizations = AppLocalizations.of(context)!;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.key),
          onPressed: _createDictionary,
          child: Text(localizations.dictionary),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.create_new_folder),
          onPressed: _editDictionaryFolder,
          child: Text(localizations.folder),
        ),
      ],
      builder: (context, controller, child) {
        void toggleMenu() {
          controller.isOpen ? controller.close() : controller.open();
        }

        if (elevated) {
          return ElevatedButton(
            onPressed: toggleMenu,
            style: customCardButtonStyle(appState),
            child: const Icon(Icons.add),
          );
        }
        return IconButton(
          onPressed: toggleMenu,
          tooltip: localizations.create,
          icon: const Icon(Icons.add),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    final allDictionaries =
        appState.sharedPreferencesProvider.getDictionaries();
    final allDictionaryFolders =
        appState.sharedPreferencesProvider.getDictionaryFolders();
    final dictionaries = allDictionaries
        .where((dictionary) => dictionary.folderId == currentDictionaryFolderId)
        .toList();
    final dictionaryFolders = allDictionaryFolders
        .where((folder) => folder.parentId == currentDictionaryFolderId)
        .toList();
    final currentDictionaryFolder = currentDictionaryFolderId == null
        ? null
        : allDictionaryFolders.cast<DictionaryFolder?>().firstWhere(
              (folder) => folder?.id == currentDictionaryFolderId,
              orElse: () => null,
            );
    final allTags = appState.sharedPreferencesProvider.getCards();
    final allFolders = appState.sharedPreferencesProvider.getCardFolders();
    final tags =
        allTags.where((tag) => tag.folderId == currentFolderId).toList();
    final folders = allFolders
        .where((folder) => folder.parentId == currentFolderId)
        .toList();
    final currentFolder = currentFolderId == null
        ? null
        : allFolders.cast<CardFolder?>().firstWhere(
              (folder) => folder?.id == currentFolderId,
              orElse: () => null,
            );
    var localizations = AppLocalizations.of(context)!;
    final isCompact = MediaQuery.of(context).size.width < 700;
    late VoidCallback importCard;
    late VoidCallback importDictionary;

    Widget sectionHeader(String title, List<Widget> actions) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: isCompact
            ? Row(
                children: [
                  SizedBox(width: actions.length * 48),
                  Expanded(
                      child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  )),
                  Row(mainAxisSize: MainAxisSize.min, children: actions),
                ],
              )
            : Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.saved_cards),
        leading: currentFolder == null
            ? null
            : IconButton(
                tooltip: localizations.parent_folder,
                onPressed: () => setState(
                  () => currentFolderId = currentFolder.parentId,
                ),
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Card(
                child: Column(children: [
              sectionHeader(
                currentFolder?.name ?? localizations.cards,
                [
                  IconButton(
                    onPressed: () => importCard(),
                    icon: const Icon(Icons.file_upload),
                  ),
                  _createMenuButton(appState, elevated: false),
                ],
              ),
              Visibility(
                visible: !isCompact,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: importCard = () async {
                                  PlatformFile? result =
                                      await FilePicker.pickFile();

                                  if (result != null) {
                                    File file = File(result.path!);
                                    var contents = await file.readAsBytes();
                                    try {
                                      var string =
                                          const Utf8Decoder().convert(contents);
                                      dynamic decodedJson;
                                      try {
                                        decodedJson = jsonDecode(string);
                                      } catch (_) {
                                        // Non-JSON formats are handled below.
                                      }
                                      if (decodedJson is Map &&
                                          decodedJson['format'] ==
                                              'chameleon-ultra-gui-folder') {
                                        await _importFolderSource(string);
                                        return;
                                      }
                                      var tags = appState
                                          .sharedPreferencesProvider
                                          .getCards();
                                      CardSave tag;
                                      if (string.contains(
                                          "\"Created\": \"proxmark3\",")) {
                                        // PM3 JSON
                                        tag = pm3JsonToCardSave(string);
                                      } else if (string.contains(
                                          "Filetype: Flipper NFC device")) {
                                        // Flipper NFC
                                        tag = flipperNfcToCardSave(string);
                                      } else if (string
                                          .contains("+Sector: 0")) {
                                        // Mifare Classic Tool
                                        tag = mctToCardSave(string);
                                      } else if (string.contains(
                                          "Filetype: Flipper RFID key")) {
                                        // Flipper RFID
                                        tag = flipperRfidToCardSave(string);
                                      } else {
                                        tag = CardSave.fromJson(string);
                                      }

                                      tag.name = basename(file.path)
                                              .contains('.')
                                          ? basename(file.path).split('.')[0]
                                          : basename(file.path);
                                      tag.folderId = currentFolderId;
                                      tags.add(tag);
                                      appState.sharedPreferencesProvider
                                          .setCards(tags);
                                      appState.changesMade();
                                    } catch (_) {
                                      selectedType =
                                          getTagTypeByDumpSize(contents.length);

                                      if (selectedType == TagType.unknown) {
                                        return;
                                      }

                                      bool hasUid4Support = false;
                                      Uint8List uid4 = Uint8List(0);
                                      Uint8List uid7 = Uint8List(0);
                                      int uid4Sak = 0;
                                      Uint8List uid4Atqa = Uint8List(0);
                                      int uid7Sak = 0;
                                      Uint8List uid7Atqa = Uint8List(0);

                                      if (isMifareClassic(selectedType)) {
                                        hasUid4Support = true;
                                        uid4 = contents.sublist(0, 4);
                                        uid7 = contents.sublist(0, 7);
                                        uid4Sak = contents[5];
                                        uid4Atqa = Uint8List.fromList(
                                            [contents[7], contents[6]]);
                                      } else if (isMifareUltralight(
                                          selectedType)) {
                                        uid7Atqa =
                                            Uint8List.fromList([0x00, 0x44]);
                                        uid7 = Uint8List.fromList([
                                          ...contents.sublist(0, 3),
                                          ...contents.sublist(4, 8)
                                        ]);
                                      }

                                      final uid4Controller =
                                          TextEditingController(
                                              text: bytesToHexSpace(uid4));
                                      final sak4Controller =
                                          TextEditingController(
                                              text: bytesToHex(
                                                  Uint8List.fromList(
                                                      [uid4Sak])));
                                      final atqa4Controller =
                                          TextEditingController(
                                              text: bytesToHexSpace(uid4Atqa));
                                      final uid7Controller =
                                          TextEditingController(
                                              text: bytesToHexSpace(uid7));
                                      final sak7Controller =
                                          TextEditingController(
                                              text: bytesToHex(
                                                  Uint8List.fromList(
                                                      [uid7Sak])));
                                      final atqa7Controller =
                                          TextEditingController(
                                              text: bytesToHexSpace(uid7Atqa));
                                      final nameController =
                                          TextEditingController(text: "");

                                      if (!context.mounted) {
                                        return;
                                      }

                                      await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: Text(
                                                localizations.correct_tag_data),
                                            content: StatefulBuilder(builder:
                                                (BuildContext context,
                                                    StateSetter setState) {
                                              return SingleChildScrollView(
                                                  child: Column(children: [
                                                if (hasUid4Support)
                                                  Column(children: [
                                                    const SizedBox(height: 20),
                                                    Text(localizations
                                                        .uid_len(4)),
                                                    const SizedBox(height: 10),
                                                    TextFormField(
                                                      controller:
                                                          uid4Controller,
                                                      inputFormatters:
                                                          hexFormatter,
                                                      validator: (value) =>
                                                          validateHex(
                                                        value,
                                                        localizations,
                                                        exactBytes: 4,
                                                        fieldName:
                                                            localizations.uid,
                                                      ),
                                                      decoration: InputDecoration(
                                                          labelText:
                                                              localizations.uid,
                                                          hintText: localizations
                                                              .enter_something(
                                                                  "UID")),
                                                    ),
                                                    const SizedBox(height: 20),
                                                    TextFormField(
                                                      controller:
                                                          sak4Controller,
                                                      inputFormatters:
                                                          hexFormatter,
                                                      validator: (value) =>
                                                          validateHex(
                                                        value,
                                                        localizations,
                                                        exactBytes: 1,
                                                        fieldName:
                                                            localizations.sak,
                                                      ),
                                                      decoration: InputDecoration(
                                                          labelText:
                                                              localizations.sak,
                                                          hintText: localizations
                                                              .enter_something(
                                                                  "SAK")),
                                                    ),
                                                    const SizedBox(height: 20),
                                                    TextFormField(
                                                      controller:
                                                          atqa4Controller,
                                                      inputFormatters:
                                                          hexFormatter,
                                                      validator: (value) =>
                                                          validateHex(
                                                        value,
                                                        localizations,
                                                        exactBytes: 2,
                                                        fieldName:
                                                            localizations.atqa,
                                                      ),
                                                      decoration: InputDecoration(
                                                          labelText:
                                                              localizations
                                                                  .atqa,
                                                          hintText: localizations
                                                              .enter_something(
                                                                  "ATQA")),
                                                    ),
                                                    const SizedBox(height: 40),
                                                  ]),
                                                Column(children: [
                                                  Text(
                                                      localizations.uid_len(7)),
                                                  const SizedBox(height: 10),
                                                  TextFormField(
                                                    controller: uid7Controller,
                                                    inputFormatters:
                                                        hexFormatter,
                                                    validator: (value) =>
                                                        validateHex(
                                                      value,
                                                      localizations,
                                                      exactBytes: 7,
                                                      fieldName:
                                                          localizations.uid,
                                                    ),
                                                    decoration: InputDecoration(
                                                        labelText:
                                                            localizations.uid,
                                                        hintText: localizations
                                                            .enter_something(
                                                                "UID")),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  TextFormField(
                                                    controller: sak7Controller,
                                                    inputFormatters:
                                                        hexFormatter,
                                                    validator: (value) =>
                                                        validateHex(
                                                      value,
                                                      localizations,
                                                      exactBytes: 1,
                                                      fieldName:
                                                          localizations.sak,
                                                    ),
                                                    decoration: InputDecoration(
                                                        labelText:
                                                            localizations.sak,
                                                        hintText: localizations
                                                            .enter_something(
                                                                "SAK")),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  TextFormField(
                                                    controller: atqa7Controller,
                                                    inputFormatters:
                                                        hexFormatter,
                                                    validator: (value) =>
                                                        validateHex(
                                                      value,
                                                      localizations,
                                                      exactBytes: 2,
                                                      fieldName:
                                                          localizations.atqa,
                                                    ),
                                                    decoration: InputDecoration(
                                                        labelText:
                                                            localizations.atqa,
                                                        hintText: localizations
                                                            .enter_something(
                                                                "ATQA")),
                                                  ),
                                                  const SizedBox(height: 40)
                                                ]),
                                                TextFormField(
                                                  controller: nameController,
                                                  validator: (value) =>
                                                      validateName(
                                                          value, localizations),
                                                  decoration: InputDecoration(
                                                      labelText:
                                                          localizations.name,
                                                      hintText: localizations
                                                          .enter_name_of_card),
                                                ),
                                                DropdownButton<TagType>(
                                                  value: selectedType,
                                                  items: getTagTypesByFrequency(
                                                          TagFrequency.hf)
                                                      .map<
                                                              DropdownMenuItem<
                                                                  TagType>>(
                                                          (TagType type) {
                                                    return DropdownMenuItem<
                                                        TagType>(
                                                      value: type,
                                                      child: Text(
                                                          chameleonTagToString(
                                                              type,
                                                              localizations)),
                                                    );
                                                  }).toList(),
                                                  onChanged:
                                                      (TagType? newValue) {
                                                    setState(() {
                                                      selectedType = newValue!;
                                                    });
                                                    appState.changesMade();
                                                  },
                                                )
                                              ]));
                                            }),
                                            actions: [
                                              if (hasUid4Support)
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    List<Uint8List> blocks = [];
                                                    int blockSize =
                                                        isMifareClassic(
                                                                selectedType)
                                                            ? 16
                                                            : 4;

                                                    for (var i = 0;
                                                        i < contents.length;
                                                        i += blockSize) {
                                                      if (i + blockSize >
                                                          contents.length) {
                                                        break;
                                                      }
                                                      blocks.add(
                                                          contents.sublist(i,
                                                              i + blockSize));
                                                    }

                                                    var tags = appState
                                                        .sharedPreferencesProvider
                                                        .getCards();

                                                    if (sak4Controller
                                                                .text.length !=
                                                            2 ||
                                                        atqa4Controller
                                                                .text.length !=
                                                            5) {
                                                      return showDialog(
                                                        context: context,
                                                        barrierDismissible:
                                                            true,
                                                        builder: (_) =>
                                                            AlertDialog(
                                                                title: Text(
                                                                    localizations
                                                                        .error),
                                                                actions: [
                                                                  ElevatedButton(
                                                                    onPressed:
                                                                        () {
                                                                      Navigator.pop(
                                                                          context);
                                                                    },
                                                                    child: Text(
                                                                        localizations
                                                                            .ok),
                                                                  ),
                                                                ],
                                                                content: Text(
                                                                    localizations
                                                                        .invalid_input)),
                                                      );
                                                    }

                                                    var tag = CardSave(
                                                        name:
                                                            nameController.text,
                                                        sak: hexToBytes(
                                                            sak4Controller
                                                                .text)[0],
                                                        atqa: hexToBytes(
                                                            atqa4Controller
                                                                .text),
                                                        uid:
                                                            uid4Controller.text,
                                                        tag: selectedType,
                                                        data: blocks);
                                                    tag.folderId =
                                                        currentFolderId;
                                                    tags.add(tag);
                                                    appState
                                                        .sharedPreferencesProvider
                                                        .setCards(tags);
                                                    appState.changesMade();
                                                    Navigator.pop(context);
                                                  },
                                                  child: Text(localizations
                                                      .save_as(localizations
                                                          .x_byte_uid(4))),
                                                ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  List<Uint8List> blocks = [];
                                                  int blockSize =
                                                      isMifareClassic(
                                                              selectedType)
                                                          ? 16
                                                          : 4;

                                                  for (var i = 0;
                                                      i < contents.length;
                                                      i += blockSize) {
                                                    blocks.add(contents.sublist(
                                                        i, i + blockSize));
                                                  }

                                                  var tags = appState
                                                      .sharedPreferencesProvider
                                                      .getCards();

                                                  if (sak7Controller
                                                              .text.length !=
                                                          2 ||
                                                      atqa7Controller
                                                              .text.length !=
                                                          5) {
                                                    return showDialog(
                                                      context: context,
                                                      barrierDismissible: true,
                                                      builder: (_) =>
                                                          AlertDialog(
                                                              title: Text(
                                                                  localizations
                                                                      .error),
                                                              actions: [
                                                                ElevatedButton(
                                                                  onPressed:
                                                                      () {
                                                                    Navigator.pop(
                                                                        context);
                                                                  },
                                                                  child: Text(
                                                                      localizations
                                                                          .ok),
                                                                ),
                                                              ],
                                                              content: Text(
                                                                  localizations
                                                                      .invalid_input)),
                                                    );
                                                  }

                                                  var tag = CardSave(
                                                      name: nameController.text,
                                                      sak: hexToBytes(
                                                          sak7Controller
                                                              .text)[0],
                                                      atqa: hexToBytes(
                                                          atqa7Controller.text),
                                                      uid: uid7Controller.text,
                                                      tag: selectedType,
                                                      data: blocks);
                                                  tag.folderId =
                                                      currentFolderId;
                                                  tags.add(tag);
                                                  appState
                                                      .sharedPreferencesProvider
                                                      .setCards(tags);
                                                  appState.changesMade();
                                                  Navigator.pop(context);
                                                },
                                                child: Text(localizations
                                                    .save_as(localizations
                                                        .x_byte_uid(7))),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.pop(
                                                      context); // Close the modal without saving
                                                },
                                                child:
                                                    Text(localizations.cancel),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    }
                                  }
                                },
                                style: customCardButtonStyle(appState),
                                child: const Icon(Icons.file_upload),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _createMenuButton(
                                appState,
                                elevated: true,
                              ),
                            ),
                          ],
                        ),
                      )
                    ]),
              ),
              Expanded(
                  child: SingleChildScrollView(
                      child: AlignedGridView.count(
                          clipBehavior: Clip.antiAlias,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(10),
                          crossAxisCount:
                              MediaQuery.of(context).size.width >= 700 ? 2 : 1,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          itemCount: folders.length + tags.length,
                          shrinkWrap: true,
                          itemBuilder: (BuildContext context, int index) {
                            if (index < folders.length) {
                              final folder = folders[index];
                              final subtreeIds =
                                  _folderTreeIds(folder.id, allFolders);
                              final cardCount = allTags
                                  .where((card) =>
                                      subtreeIds.contains(card.folderId))
                                  .length;
                              return ElementButton(
                                icon: Icons.folder,
                                iconColor: folder.color,
                                firstLine: folder.name,
                                secondLine:
                                    localizations.folder_card_count(cardCount),
                                itemIndex: index,
                                onPressed: () => setState(
                                  () => currentFolderId = folder.id,
                                ),
                                children: [
                                  IconButton(
                                    tooltip: localizations.move_folder,
                                    onPressed: () => _moveFolder(folder),
                                    icon: const Icon(
                                        Icons.drive_file_move_outline),
                                  ),
                                  IconButton(
                                    tooltip: localizations.edit_folder,
                                    onPressed: () => _editFolder(folder),
                                    icon: const Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    tooltip: localizations.export_folder,
                                    onPressed: () => _exportFolder(folder),
                                    icon: const Icon(Icons.download),
                                  ),
                                  IconButton(
                                    tooltip: localizations.delete_folder,
                                    onPressed: () => _deleteFolder(folder),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              );
                            }
                            final tag = tags[index - folders.length];
                            return ElementButton(
                              icon: (chameleonTagToFrequency(tag.tag) ==
                                      TagFrequency.hf)
                                  ? Icons.credit_card
                                  : Icons.wifi,
                              iconColor: tag.color,
                              firstLine: tag.name.isEmpty ? "⠀" : tag.name,
                              secondLine:
                                  chameleonCardToString(tag, localizations),
                              itemIndex: index,
                              onPressed: () {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return CardViewMenu(
                                        tagSave: tag,
                                        onMove: _moveCard,
                                      );
                                    });
                              },
                              children: [
                                IconButton(
                                  tooltip: localizations.move_card,
                                  onPressed: () => _moveCard(tag),
                                  icon:
                                      const Icon(Icons.drive_file_move_outline),
                                ),
                                IconButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return CardEditMenu(tagSave: tag);
                                      },
                                    );
                                  },
                                  icon: const Icon(Icons.edit),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: Text(
                                              localizations.select_save_format),
                                          actions: [
                                            ElevatedButton(
                                              onPressed: () async {
                                                await saveTag(
                                                    tag, context, true);
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                              child: Text(localizations
                                                  .save_as(".bin")),
                                            ),
                                            ElevatedButton(
                                              onPressed: () async {
                                                await saveTag(
                                                    tag, context, false);
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              },
                                              child: Text(localizations
                                                  .save_as(".json")),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  icon: const Icon(Icons.download),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    if (appState.sharedPreferencesProvider
                                            .getConfirmDelete() ==
                                        true) {
                                      var confirm = await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return ConfirmDeletionMenu(
                                              thingBeingDeleted: tag.name);
                                        },
                                      );

                                      if (confirm != true) {
                                        return;
                                      }
                                    }
                                    var tags = appState
                                        .sharedPreferencesProvider
                                        .getCards();
                                    List<CardSave> output = [];
                                    for (var tagTest in tags) {
                                      if (tagTest.id != tag.id) {
                                        output.add(tagTest);
                                      }
                                    }
                                    appState.sharedPreferencesProvider
                                        .setCards(output);
                                    appState.changesMade();
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            );
                          }))),
            ])),
          ),
          Expanded(
            child: Card(
                child: Column(children: [
              sectionHeader(
                currentDictionaryFolder?.name ?? localizations.dictionaries,
                [
                  if (currentDictionaryFolder != null)
                    IconButton(
                      tooltip: localizations.parent_folder,
                      onPressed: () => setState(() =>
                          currentDictionaryFolderId =
                              currentDictionaryFolder.parentId),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  IconButton(
                    onPressed: () => importDictionary(),
                    icon: const Icon(Icons.upload),
                  ),
                  _dictionaryCreateMenuButton(appState, elevated: false),
                ],
              ),
              Visibility(
                visible: !isCompact,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: Row(children: [
                          if (currentDictionaryFolder != null) ...[
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => setState(() =>
                                    currentDictionaryFolderId =
                                        currentDictionaryFolder.parentId),
                                style: customCardButtonStyle(appState),
                                child: const Icon(Icons.arrow_back),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              onPressed: importDictionary = () async {
                                PlatformFile? result =
                                    await FilePicker.pickFile();

                                if (result != null) {
                                  File file = File(result.path!);
                                  String contents;
                                  try {
                                    contents = const Utf8Decoder()
                                        .convert(await file.readAsBytes());
                                  } catch (e) {
                                    return;
                                  }

                                  dynamic decodedJson;
                                  try {
                                    decodedJson = jsonDecode(contents);
                                  } catch (_) {
                                    // Plain dictionary files are handled below.
                                  }
                                  if (decodedJson is Map &&
                                      decodedJson['format'] ==
                                          'chameleon-ultra-gui-dictionary-folder') {
                                    await _importDictionaryFolderSource(
                                        contents);
                                    return;
                                  }

                                  var dictionaries = appState
                                      .sharedPreferencesProvider
                                      .getDictionaries();

                                  Dictionary dictionary = Dictionary.fromString(
                                      contents,
                                      name: result.name.split(".")[0]);
                                  dictionary.folderId =
                                      currentDictionaryFolderId;

                                  if (dictionary.keys.isEmpty) {
                                    return;
                                  }

                                  dictionaries.add(dictionary);

                                  appState.sharedPreferencesProvider
                                      .setDictionaries(dictionaries);
                                  appState.changesMade();
                                }
                              },
                              style: customCardButtonStyle(appState),
                              child: const Icon(Icons.upload),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dictionaryCreateMenuButton(
                              appState,
                              elevated: true,
                            ),
                          ),
                        ]),
                      )
                    ]),
              ),
              Expanded(
                  child: SingleChildScrollView(
                      child: AlignedGridView.count(
                          clipBehavior: Clip.antiAlias,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(10),
                          crossAxisCount:
                              MediaQuery.of(context).size.width >= 700 ? 2 : 1,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          itemCount:
                              dictionaryFolders.length + dictionaries.length,
                          shrinkWrap: true,
                          itemBuilder: (BuildContext context, int index) {
                            if (index < dictionaryFolders.length) {
                              final folder = dictionaryFolders[index];
                              final subtreeIds = _dictionaryFolderTreeIds(
                                  folder.id, allDictionaryFolders);
                              final dictionaryCount = allDictionaries
                                  .where((dictionary) =>
                                      subtreeIds.contains(dictionary.folderId))
                                  .length;
                              return ElementButton(
                                icon: Icons.folder,
                                iconColor: folder.color,
                                firstLine: folder.name,
                                secondLine: localizations
                                    .folder_dictionary_count(dictionaryCount),
                                itemIndex: index,
                                onPressed: () => setState(
                                  () => currentDictionaryFolderId = folder.id,
                                ),
                                children: [
                                  IconButton(
                                    tooltip: localizations.move_folder,
                                    onPressed: () =>
                                        _moveDictionaryFolder(folder),
                                    icon: const Icon(
                                        Icons.drive_file_move_outline),
                                  ),
                                  IconButton(
                                    tooltip: localizations.edit_folder,
                                    onPressed: () =>
                                        _editDictionaryFolder(folder),
                                    icon: const Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    tooltip: localizations.export_folder,
                                    onPressed: () =>
                                        _exportDictionaryFolder(folder),
                                    icon: const Icon(Icons.download),
                                  ),
                                  IconButton(
                                    tooltip: localizations.delete_folder,
                                    onPressed: () =>
                                        _deleteDictionaryFolder(folder),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              );
                            }
                            final dictionary =
                                dictionaries[index - dictionaryFolders.length];
                            return ElementButton(
                              icon: Icons.key,
                              iconColor: dictionary.color,
                              firstLine: dictionary.name,
                              secondLine:
                                  "${localizations.key_count}: ${dictionary.keys.length}",
                              itemIndex: index,
                              onPressed: () {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return DictionaryViewMenu(
                                        dictionary: dictionary,
                                        onMove: _moveDictionary,
                                      );
                                    });
                              },
                              children: [
                                IconButton(
                                  tooltip: localizations.move_dictionary,
                                  onPressed: () => _moveDictionary(dictionary),
                                  icon:
                                      const Icon(Icons.drive_file_move_outline),
                                ),
                                IconButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return DictionaryEditMenu(
                                            dictionary: dictionary);
                                      },
                                    );
                                  },
                                  icon: const Icon(Icons.edit),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    await FilePicker.saveFile(
                                      dialogTitle:
                                          '${localizations.output_file}:',
                                      fileName: '${dictionary.name}.dic',
                                      bytes: dictionary.toFile(),
                                    );
                                  },
                                  icon: const Icon(Icons.download),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    if (appState.sharedPreferencesProvider
                                            .getConfirmDelete() ==
                                        true) {
                                      var confirm = await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return ConfirmDeletionMenu(
                                              thingBeingDeleted:
                                                  dictionary.name);
                                        },
                                      );

                                      if (confirm != true) {
                                        return;
                                      }
                                    }
                                    var dictionaries = appState
                                        .sharedPreferencesProvider
                                        .getDictionaries();
                                    List<Dictionary> output = [];
                                    for (var dict in dictionaries) {
                                      if (dict.id != dictionary.id) {
                                        output.add(dict);
                                      }
                                    }
                                    appState.sharedPreferencesProvider
                                        .setDictionaries(output);
                                    appState.changesMade();
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            );
                          }))),
            ])),
          ),
        ],
      ),
    );
  }

  Future<String?> dictMergeDialog(BuildContext context, Dictionary mergeDict) {
    var appState = context.read<ChameleonGUIState>();
    var dicts = appState.sharedPreferencesProvider.getDictionaries();

    dicts.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: DictMergeDelegate(dicts, mergeDict),
    );
  }
}

class DictMergeDelegate extends SearchDelegate<String> {
  final List<Dictionary> dicts;
  final Dictionary mergeDict;
  List<bool> selectedDicts = [];

  DictMergeDelegate(this.dicts, this.mergeDict) {
    selectedDicts = List.filled(dicts.length, false);
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
      const SizedBox(width: 10),
      IconButton(
        icon: const Icon(Icons.merge),
        onPressed: () {
          List<Dictionary> selectedForMerge = [];
          List<Dictionary> output = dicts;

          // Get selected dicts
          for (var i = 0; i < selectedDicts.length; i++) {
            if (selectedDicts[i]) {
              selectedForMerge.add(dicts[i]);
            }
          }

          // Merge
          for (var dict in selectedForMerge) {
            mergeDict.keys = mergeDict.keys + dict.keys;
          }

          // Deduplicate
          mergeDict.keys = <int, Uint8List>{
            for (var key in mergeDict.keys) Object.hashAll(key): key
          }.values.toList();

          // Replace
          for (var i = 0; i < output.length; i++) {
            if (output[i].id == mergeDict.id) {
              output[i] = mergeDict;
            }
          }

          appState.sharedPreferencesProvider.setDictionaries(output);

          Navigator.pop(context);
          appState.changesMade();
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));
    var localizations = AppLocalizations.of(context)!;

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        if (dict.id == mergeDict.id) {
          return Container();
        }
        return CheckboxListTile(
          value: selectedDicts[index],
          title: Text(dict.name),
          secondary: Icon(Icons.key, color: dict.color),
          subtitle: Text(
              "${dict.keys.length.toString()} ${localizations.total_keys.toLowerCase()}"),
          onChanged: (value) {},
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));
    var localizations = AppLocalizations.of(context)!;

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        var appState = context.read<ChameleonGUIState>();
        if (dict.id == mergeDict.id) {
          return Container();
        }
        return CheckboxListTile(
          value: selectedDicts[index],
          title: Text(dict.name),
          secondary: Icon(Icons.key, color: dict.color),
          subtitle: Text(
              "${dict.keys.length.toString()} ${localizations.total_keys.toLowerCase()}"),
          onChanged: (value) {
            selectedDicts[index] = value!;
            appState.changesMade();
          },
        );
      },
    );
  }
}
