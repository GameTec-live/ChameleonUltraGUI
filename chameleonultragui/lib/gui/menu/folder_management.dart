import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class FolderManagementMenu extends StatefulWidget {
  const FolderManagementMenu({super.key});

  @override
  FolderManagementMenuState createState() => FolderManagementMenuState();
}

class FolderManagementMenuState extends State<FolderManagementMenu> {
  String? selectedFolderId;
  final TextEditingController folderNameController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    searchController.addListener(() {
      setState(() {
        searchQuery = searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    folderNameController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _createFolder() {
    var localizations = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(localizations.create_folder),
          content: TextFormField(
            controller: folderNameController,
            decoration: InputDecoration(
              labelText: localizations.folder_name,
              hintText: localizations.enter_folder_name,
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () {
                if (folderNameController.text.isNotEmpty) {
                  var appState = context.read<ChameleonGUIState>();
                  appState.sharedPreferencesProvider.createFolder(
                    folderNameController.text,
                    parentId: selectedFolderId,
                  );
                  appState.changesMade();
                  folderNameController.clear();
                  setState(() {});
                  Navigator.of(context).pop();
                }
              },
              child: Text(localizations.create),
            ),
          ],
        );
      },
    );
  }

  void _renameFolder(CardFolder folder) {
    var localizations = AppLocalizations.of(context)!;
    folderNameController.text = folder.name;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(localizations.rename_folder),
          content: TextFormField(
            controller: folderNameController,
            decoration: InputDecoration(
              labelText: localizations.folder_name,
              hintText: localizations.enter_folder_name,
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () {
                if (folderNameController.text.isNotEmpty) {
                  var appState = context.read<ChameleonGUIState>();
                  appState.sharedPreferencesProvider.renameFolder(
                    folder.id,
                    folderNameController.text,
                  );
                  appState.changesMade();
                  folderNameController.clear();
                  setState(() {});
                  Navigator.of(context).pop();
                }
              },
              child: Text(localizations.save),
            ),
          ],
        );
      },
    );
  }

  void _deleteFolder(CardFolder folder) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    var cardsInFolder = appState.sharedPreferencesProvider.getCardsInFolder(folder.id);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        bool moveCardsToParent = true;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(localizations.delete_folder),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.confirm_deletion_text(folder.name)),
                  if (cardsInFolder.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('${cardsInFolder.length} ${localizations.cards.toLowerCase()} ${localizations.cards.toLowerCase().endsWith('s') ? 'are' : 'is'} in this folder:'),
                    const SizedBox(height: 8),
                    RadioListTile<bool>(
                      title: Text(localizations.move_cards_to_parent),
                      value: true,
                      groupValue: moveCardsToParent,
                      onChanged: (value) {
                        setDialogState(() {
                          moveCardsToParent = value!;
                        });
                      },
                    ),
                    RadioListTile<bool>(
                      title: Text(localizations.delete_cards_with_folder),
                      value: false,
                      groupValue: moveCardsToParent,
                      onChanged: (value) {
                        setDialogState(() {
                          moveCardsToParent = value!;
                        });
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(localizations.cancel),
                ),
                TextButton(
                  onPressed: () {
                    appState.sharedPreferencesProvider.deleteFolder(
                      folder.id,
                      moveCardsToParent: moveCardsToParent,
                    );
                    appState.changesMade();
                    setState(() {});
                    Navigator.of(context).pop();
                  },
                  child: Text(localizations.delete),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFolderTree(String? parentId, {int indent = 0}) {
    var appState = context.watch<ChameleonGUIState>();
    var folders = appState.sharedPreferencesProvider.getSubfolders(parentId);
    var cards = appState.sharedPreferencesProvider.getCardsInFolder(parentId);
    var localizations = AppLocalizations.of(context)!;

    List<Widget> widgets = [];

    // For each folder, show the folder followed immediately by its children
    for (var folder in folders) {
      // Filter folders based on search query
      bool folderMatches = searchQuery.isEmpty || 
          folder.name.toLowerCase().contains(searchQuery);
      
      // Check if any children match the search
      bool hasMatchingChildren = _hasMatchingChildren(folder.id);
      
      // Show folder if it matches or has matching children
      if (folderMatches || hasMatchingChildren) {
        // Add the folder itself
        int folderCardCount = appState.sharedPreferencesProvider.getCardsInFolder(folder.id).length;
        int subfolderCount = appState.sharedPreferencesProvider.getSubfolders(folder.id).length;
        
        widgets.add(Container(
          margin: EdgeInsets.only(left: indent * 16.0),
          child: Card(
            child: ListTile(
              leading: Icon(
                folderCardCount > 0 || subfolderCount > 0 ? Icons.folder : Icons.folder_outlined, 
                color: folder.color
              ),
              title: Text(folder.name),
              subtitle: Text(
                folderCardCount > 0
                    ? '$folderCardCount ${localizations.cards.toLowerCase()}${subfolderCount > 0 ? ' • $subfolderCount ${subfolderCount == 1 ? localizations.folder.toLowerCase() : localizations.folders.toLowerCase()}' : ''}'
                    : subfolderCount > 0
                        ? '$subfolderCount ${subfolderCount == 1 ? localizations.folder.toLowerCase() : localizations.folders.toLowerCase()}'
                        : localizations.empty
              ),
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        const Icon(Icons.edit),
                        const SizedBox(width: 8),
                        Text(localizations.rename_folder),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete),
                        const SizedBox(width: 8),
                        Text(localizations.delete_folder),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      _renameFolder(folder);
                      break;
                    case 'delete':
                      _deleteFolder(folder);
                      break;
                  }
                },
              ),
              onTap: () {
                setState(() {
                  // Toggle selection: if already selected, deselect; otherwise select
                  selectedFolderId = selectedFolderId == folder.id ? null : folder.id;
                });
              },
              selected: selectedFolderId == folder.id,
            ),
          ),
        ));

        // Add the folder's children (subfolders and cards) immediately after
        widgets.add(_buildFolderTree(folder.id, indent: indent + 1));
      }
    }
    
    // Show cards in current folder (only for the current level)
    for (var card in cards) {
      // Filter cards based on search query
      bool cardMatches = searchQuery.isEmpty || 
          card.name.toLowerCase().contains(searchQuery) ||
          card.uid.toLowerCase().contains(searchQuery);
      
      if (cardMatches) {
        widgets.add(Container(
          margin: EdgeInsets.only(left: indent * 16.0 + 16.0),
          child: Card(
            child: ListTile(
              leading: Icon(
                Icons.credit_card,
                color: card.color,
              ),
              title: Text(card.name.isEmpty ? localizations.no_name : card.name),
              subtitle: Text(card.uid),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  appState.sharedPreferencesProvider.moveCardToFolder(card.id, null);
                  appState.changesMade();
                  setState(() {});
                },
                tooltip: localizations.remove_from_folder,
              ),
            ),
          ),
        ));
      }
    }

    return Column(children: widgets);
  }

  bool _hasMatchingChildren(String folderId) {
    var appState = context.read<ChameleonGUIState>();
    
    // Check if any cards in this folder match
    var cards = appState.sharedPreferencesProvider.getCardsInFolder(folderId);
    for (var card in cards) {
      if (card.name.toLowerCase().contains(searchQuery) ||
          card.uid.toLowerCase().contains(searchQuery)) {
        return true;
      }
    }
    
    // Check if any subfolders match or have matching children
    var subfolders = appState.sharedPreferencesProvider.getSubfolders(folderId);
    for (var subfolder in subfolders) {
      if (subfolder.name.toLowerCase().contains(searchQuery) ||
          _hasMatchingChildren(subfolder.id)) {
        return true;
      }
    }
    
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.folder_management),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.organize_cards),
            const SizedBox(height: 16),
            // Search bar
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: '${localizations.search}...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            const SizedBox(height: 16),
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                child: _buildFolderTree(null),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _createFolder,
          icon: const Icon(Icons.create_new_folder),
          label: Text(localizations.create_folder),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(localizations.close),
        ),
      ],
    );
  }
}
