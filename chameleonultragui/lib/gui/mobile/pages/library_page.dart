import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/import.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/view.dart';
import 'package:chameleonultragui/gui/mobile/pages/writer_page.dart';
import 'package:chameleonultragui/gui/mobile/widgets/action_sheet.dart';
import 'package:chameleonultragui/gui/mobile/widgets/helpers.dart';
import 'package:chameleonultragui/gui/mobile/widgets/message_view.dart';
import 'package:chameleonultragui/gui/mobile/widgets/slot_upload.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/slot_loader.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

enum _LibraryFilter { all, hf, lf }

class MobileLibraryPage extends StatefulWidget {
  const MobileLibraryPage({super.key, this.pickMode = false});

  /// When true the page is pushed as a picker: tapping a card pops with the
  /// selected [CardSave] and no management actions are offered.
  final bool pickMode;

  @override
  State<MobileLibraryPage> createState() => _MobileLibraryPageState();
}

class _MobileLibraryPageState extends State<MobileLibraryPage> {
  String _query = '';
  _LibraryFilter _filter = _LibraryFilter.all;

  bool _isConnected(BuildContext context) {
    final connector = context.read<ChameleonGUIState>().connector;
    return connector != null && connector.connected && !connector.isDFU;
  }

  Future<void> _import() async {
    await importCardFromFile(context);
  }

  void _openFolders() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SavedCardsPage(section: SavedCardsSection.cards),
      ),
    );
  }

  void _view(CardSave card) {
    showDialog(
      context: context,
      builder: (_) => CardViewMenu(tagSave: card, onMove: _moveCard),
    );
  }

  void _showActions(CardSave card) {
    final l = AppLocalizations.of(context)!;
    final connected = _isConnected(context);
    final hasFolders = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getCardFolders()
        .isNotEmpty;
    final name = card.name.isEmpty ? l.no_name : card.name;

    showActionSheet(
      context,
      title: name,
      subtitle: chameleonCardToString(card, l),
      actions: [
        SheetAction(
          icon: Icons.visibility,
          label: l.card,
          onTap: () => _view(card),
        ),
        SheetAction(
          icon: Icons.edit,
          label: l.edit_card,
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => CardEditMenu(tagSave: card),
            );
          },
        ),
        SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: l.rename,
          onTap: () => _rename(card),
        ),
        SheetAction(
          icon: Icons.nfc,
          label: l.load_into_slot,
          enabled: !connected || canLoadCardIntoSlot(card),
          onTap: () {
            if (!_isConnected(context)) {
              showDeviceRequired(context);
              return;
            }
            pickSlotAndLoadCard(context, card);
          },
        ),
        SheetAction(
          icon: Icons.system_update_alt,
          label: l.write_to_magic_card,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MobileWriterPage(card: card)),
            );
          },
        ),
        SheetAction(
          icon: Icons.download,
          label: l.save,
          onTap: () => _export(card),
        ),
        if (hasFolders)
          SheetAction(
            icon: Icons.drive_file_move_outline,
            label: l.move_card,
            onTap: () => _moveCard(card),
          ),
        SheetAction(
          icon: Icons.delete_outline,
          label: l.delete,
          destructive: true,
          onTap: () => _delete(card),
        ),
      ],
    );
  }

  Future<void> _rename(CardSave card) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: card.name),
    );
    if (newName == null || !mounted) return;

    final appState = context.read<ChameleonGUIState>();
    final cards = appState.sharedPreferencesProvider.getCards();
    final index = cards.indexWhere((c) => c.id == card.id);
    if (index == -1) return;
    cards[index].name = newName;
    appState.sharedPreferencesProvider.setCards(cards);
    appState.changesMade();
  }

  Future<void> _export(CardSave card) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        final l = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l.select_save_format),
          actions: [
            ElevatedButton(
              onPressed: () async {
                await saveTag(card, dialogContext, true);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(l.save_as('.bin')),
            ),
            ElevatedButton(
              onPressed: () async {
                await saveTag(card, dialogContext, false);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(l.save_as('.json')),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _pickFolderDestination() async {
    final l = AppLocalizations.of(context)!;
    final folders = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getCardFolders();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l.move_to_folder),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '__root__'),
            child: ListTile(
              leading: const Icon(Icons.home),
              title: Text(l.saved_cards),
            ),
          ),
          ...folders.map(
            (folder) => SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, folder.id),
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
    if (destination == null || !mounted) return;

    final appState = context.read<ChameleonGUIState>();
    final cards = appState.sharedPreferencesProvider.getCards();
    final index = cards.indexWhere((c) => c.id == card.id);
    if (index == -1) return;
    cards[index].folderId = destination == '__root__' ? null : destination;
    appState.sharedPreferencesProvider.setCards(cards);
    appState.changesMade();
  }

  Future<void> _delete(CardSave card) async {
    if (!await confirmDeletion(context, card.name)) return;
    if (!mounted) return;

    final appState = context.read<ChameleonGUIState>();
    final cards = appState.sharedPreferencesProvider.getCards();
    cards.removeWhere((c) => c.id == card.id);
    appState.sharedPreferencesProvider.setCards(cards);
    appState.changesMade();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.watch<ChameleonGUIState>();
    final prefs = appState.sharedPreferencesProvider;
    final allCards = prefs.getCards();
    final folderNames = {
      for (final folder in prefs.getCardFolders()) folder.id: folder.name,
    };

    final query = _query.trim().toLowerCase();
    final visible =
        allCards.where((card) {
          if (_filter != _LibraryFilter.all) {
            final isHf = chameleonTagToFrequency(card.tag) == TagFrequency.hf;
            if ((_filter == _LibraryFilter.hf) != isHf) return false;
          }
          if (query.isEmpty) return true;
          return card.name.toLowerCase().contains(query) ||
              card.uid.toLowerCase().contains(query) ||
              chameleonCardToString(
                card,
                localizations,
              ).toLowerCase().contains(query);
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    Widget content;
    if (allCards.isEmpty) {
      content = MessageView(
        icon: Icons.credit_card_off,
        title: localizations.no_saved_cards,
        actions: widget.pickMode
            ? const []
            : [
                FilledButton.tonal(
                  onPressed: _import,
                  child: Text(localizations.import_card),
                ),
              ],
      );
    } else if (visible.isEmpty) {
      content = MessageView(
        icon: Icons.search_off,
        title: localizations.no_matching_cards,
      );
    } else {
      content = ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final card = visible[index];
          final isHf = chameleonTagToFrequency(card.tag) == TagFrequency.hf;
          final folderName = card.folderId == null
              ? null
              : folderNames[card.folderId];
          final baseText = chameleonCardToString(card, localizations);
          final subtitle = folderName == null
              ? baseText
              : '$baseText · $folderName';

          return ListTile(
            minTileHeight: 56,
            leading: Icon(
              isHf ? Icons.credit_card : Icons.wifi,
              color: card.color,
            ),
            title: Text(
              card.name.isEmpty ? localizations.no_name : card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: widget.pickMode
                ? () => Navigator.of(context).pop(card)
                : () => _view(card),
            onLongPress: widget.pickMode ? null : () => _showActions(card),
            trailing: widget.pickMode
                ? null
                : IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showActions(card),
                  ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pickMode
              ? localizations.select_saved_card
              : localizations.saved_cards,
        ),
        actions: widget.pickMode
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.file_upload),
                  tooltip: localizations.import_card,
                  onPressed: _import,
                ),
                IconButton(
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: localizations.folder,
                  onPressed: _openFolders,
                ),
              ],
      ),
      body: Column(
        children: [
          if (allCards.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                hintText: localizations.search_cards,
                leading: const Icon(Icons.search),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final filter in _LibraryFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (filter) {
                          _LibraryFilter.all => localizations.all,
                          _LibraryFilter.hf => localizations.hf,
                          _LibraryFilter.lf => localizations.lf,
                        }),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final localizations = AppLocalizations.of(context)!;
    final name = _controller.text.trim();
    final error = validateName(name, localizations);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.rename),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(localizations.save)),
      ],
    );
  }
}
