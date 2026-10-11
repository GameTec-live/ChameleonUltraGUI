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
  static const _rootDestination = '__root__';

  String _query = '';
  _LibraryFilter _filter = _LibraryFilter.all;

  ChameleonGUIState get _appState => context.read<ChameleonGUIState>();

  SharedPreferencesProvider get _prefs => _appState.sharedPreferencesProvider;

  bool get _isConnected {
    final connector = _appState.connector;
    return connector != null && connector.connected && !connector.isDFU;
  }

  Future<void> _import() => importCardFromFile(context);

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
    final connected = _isConnected;

    showActionSheet(
      context,
      title: _cardName(card, l),
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
            if (!_isConnected) {
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
        if (_prefs.getCardFolders().isNotEmpty)
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

  void _editCard(CardSave card, void Function(CardSave card) edit) {
    final cards = _prefs.getCards();
    final index = cards.indexWhere((c) => c.id == card.id);
    if (index == -1) return;
    edit(cards[index]);
    _prefs.setCards(cards);
    _appState.changesMade();
  }

  Future<void> _rename(CardSave card) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: card.name),
    );
    if (newName == null || !mounted) return;

    _editCard(card, (saved) => saved.name = newName);
  }

  void _export(CardSave card) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final l = AppLocalizations.of(dialogContext)!;

        Widget formatButton(String extension, bool bin) {
          return ElevatedButton(
            onPressed: () async {
              await saveTag(card, dialogContext, bin);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: Text(l.save_as(extension)),
          );
        }

        return AlertDialog(
          title: Text(l.select_save_format),
          actions: [formatButton('.bin', true), formatButton('.json', false)],
        );
      },
    );
  }

  Future<String?> _pickFolderDestination() {
    final l = AppLocalizations.of(context)!;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l.move_to_folder),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, _rootDestination),
            child: ListTile(
              leading: const Icon(Icons.home),
              title: Text(l.saved_cards),
            ),
          ),
          for (final folder in _prefs.getCardFolders())
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, folder.id),
              child: ListTile(
                leading: Icon(Icons.folder, color: folder.color),
                title: Text(folder.name),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _moveCard(CardSave card) async {
    final destination = await _pickFolderDestination();
    if (destination == null || !mounted) return;

    _editCard(
      card,
      (saved) =>
          saved.folderId = destination == _rootDestination ? null : destination,
    );
  }

  Future<void> _delete(CardSave card) async {
    if (!await confirmDeletion(context, card.name) || !mounted) return;

    final cards = _prefs.getCards()..removeWhere((c) => c.id == card.id);
    _prefs.setCards(cards);
    _appState.changesMade();
  }

  List<CardSave> _visibleCards(List<CardSave> cards, AppLocalizations l) {
    final query = _query.trim().toLowerCase();

    return cards.where((card) {
        if (_filter != _LibraryFilter.all &&
            (_filter == _LibraryFilter.hf) != _isHf(card)) {
          return false;
        }
        return query.isEmpty ||
            card.name.toLowerCase().contains(query) ||
            card.uid.toLowerCase().contains(query) ||
            chameleonCardToString(card, l).toLowerCase().contains(query);
      }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Widget _buildFilterBar(AppLocalizations l) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchBar(
            hintText: l.search_cards,
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
                      _LibraryFilter.all => l.all,
                      _LibraryFilter.hf => l.hf,
                      _LibraryFilter.lf => l.lf,
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
    );
  }

  Widget _buildCardList(
    List<CardSave> cards,
    Map<String, String> folderNames,
    AppLocalizations l,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        final folderName = folderNames[card.folderId];
        final details = chameleonCardToString(card, l);

        return ListTile(
          minTileHeight: 56,
          leading: Icon(
            _isHf(card) ? Icons.credit_card : Icons.wifi,
            color: card.color,
          ),
          title: Text(
            _cardName(card, l),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            folderName == null ? details : '$details · $folderName',
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final prefs = context.watch<ChameleonGUIState>().sharedPreferencesProvider;
    final allCards = prefs.getCards();
    final visible = _visibleCards(allCards, l);

    final Widget content;
    if (allCards.isEmpty) {
      content = MessageView(
        icon: Icons.credit_card_off,
        title: l.no_saved_cards,
        actions: widget.pickMode
            ? const []
            : [
                FilledButton.tonal(
                  onPressed: _import,
                  child: Text(l.import_card),
                ),
              ],
      );
    } else if (visible.isEmpty) {
      content = MessageView(icon: Icons.search_off, title: l.no_matching_cards);
    } else {
      content = _buildCardList(visible, {
        for (final folder in prefs.getCardFolders()) folder.id: folder.name,
      }, l);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? l.select_saved_card : l.saved_cards),
        actions: widget.pickMode
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.file_upload),
                  tooltip: l.import_card,
                  onPressed: _import,
                ),
                IconButton(
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: l.folder,
                  onPressed: _openFolders,
                ),
              ],
      ),
      body: Column(
        children: [
          if (allCards.isNotEmpty) _buildFilterBar(l),
          Expanded(child: content),
        ],
      ),
    );
  }
}

bool _isHf(CardSave card) =>
    chameleonTagToFrequency(card.tag) == TagFrequency.hf;

String _cardName(CardSave card, AppLocalizations l) =>
    card.name.isEmpty ? l.no_name : card.name;

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
