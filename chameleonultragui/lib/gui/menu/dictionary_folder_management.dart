import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class DictionaryFolderManagementMenu extends StatefulWidget {
  const DictionaryFolderManagementMenu({super.key});

  @override
  DictionaryFolderManagementMenuState createState() =>
      DictionaryFolderManagementMenuState();
}

class DictionaryFolderManagementMenuState
    extends State<DictionaryFolderManagementMenu> {
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
                  appState.sharedPreferencesProvider.createDictionaryFolder(
                    folderNameController.text,
                    selectedFolderId,
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

  void _renameFolder(DictionaryFolder folder) {
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
                  appState.sharedPreferencesProvider.renameDictionaryFolder(
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

  void _deleteFolder(DictionaryFolder folder) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.read<ChameleonGUIState>();
    var dictionariesInFolder = appState.sharedPreferencesProvider.getDictionariesInFolder(folder.id);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        bool moveDictionariesToParent = true;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(localizations.delete_folder),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.confirm_deletion_text(folder.name)),
                  if (dictionariesInFolder.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(localizations.cards_in_this_folder(dictionariesInFolder.length.toString())),
                    const SizedBox(height: 8),
                    RadioListTile<bool>(
                      title: Text(localizations.move_cards_to_parent),
                      value: true,
                      groupValue: moveDictionariesToParent,
                      onChanged: (value) {
                        setDialogState(() {
                          moveDictionariesToParent = value!;
                        });
                      },
                    ),
                    RadioListTile<bool>(
                      title: Text(localizations.delete_cards_with_folder),
                      value: false,
                      groupValue: moveDictionariesToParent,
                      onChanged: (value) {
                        setDialogState(() {
                          moveDictionariesToParent = value!;
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
                    appState.sharedPreferencesProvider.deleteDictionaryFolder(
                      folder.id,
                      moveDictionariesToParent: moveDictionariesToParent,
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
    var folders = appState.sharedPreferencesProvider.getDictionarySubfolders(parentId);
    var dictionaries = appState.sharedPreferencesProvider.getDictionariesInFolder(parentId);
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
        int folderDictionaryCount = appState.sharedPreferencesProvider.getDictionariesInFolder(folder.id).length;
        int subfolderCount = appState.sharedPreferencesProvider.getDictionarySubfolders(folder.id).length;
        
        widgets.add(Container(
          margin: EdgeInsets.only(left: indent * 16.0),
          child: Card(
            child: ListTile(
              leading: Icon(
                folderDictionaryCount > 0 || subfolderCount > 0 ? Icons.folder : Icons.folder_outlined, 
                color: folder.color
              ),
              title: Text(folder.name),
              subtitle: Text(
                folderDictionaryCount > 0
                    ? '$folderDictionaryCount ${localizations.dictionaries.toLowerCase()}${subfolderCount > 0 ? ' • $subfolderCount ${subfolderCount == 1 ? localizations.folder.toLowerCase() : localizations.folders.toLowerCase()}' : ''}'
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

        // Add the folder's children (subfolders and dictionaries) immediately after
        widgets.add(_buildFolderTree(folder.id, indent: indent + 1));
      }
    }
    
    // Show dictionaries in current folder (only for the current level)
    for (var dictionary in dictionaries) {
      // Filter dictionaries based on search query
      bool dictionaryMatches = searchQuery.isEmpty || 
          dictionary.name.toLowerCase().contains(searchQuery);
      
      if (dictionaryMatches) {
        widgets.add(Container(
          margin: EdgeInsets.only(left: indent * 16.0 + 16.0),
          child: Card(
            child: ListTile(
              leading: Icon(
                Icons.key,
                color: dictionary.color,
              ),
              title: Text(dictionary.name.isEmpty ? localizations.no_name : dictionary.name),
              subtitle: Text('${dictionary.keys.length} ${localizations.keys.toLowerCase()}'),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  appState.sharedPreferencesProvider.moveDictionaryToFolder(dictionary.id, null);
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
    
    // Check if any dictionaries in this folder match
    var dictionaries = appState.sharedPreferencesProvider.getDictionariesInFolder(folderId);
    for (var dictionary in dictionaries) {
      if (dictionary.name.toLowerCase().contains(searchQuery)) {
        return true;
      }
    }
    
    // Check if any subfolders match or have matching children
    var subfolders = appState.sharedPreferencesProvider.getDictionarySubfolders(folderId);
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
