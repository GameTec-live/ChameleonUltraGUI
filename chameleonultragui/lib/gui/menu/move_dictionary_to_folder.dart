import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class MoveDictionaryToFolderMenu extends StatefulWidget {
  final Dictionary dictionary;

  const MoveDictionaryToFolderMenu({super.key, required this.dictionary});

  @override
  MoveDictionaryToFolderMenuState createState() =>
      MoveDictionaryToFolderMenuState();
}

class MoveDictionaryToFolderMenuState extends State<MoveDictionaryToFolderMenu> {
  String? selectedFolderId;

  @override
  void initState() {
    super.initState();
    selectedFolderId = widget.dictionary.folderId;
  }

  List<Widget> _buildFolderList(
      List<DictionaryFolder> folders, String? parentId, int level) {
    List<Widget> widgets = [];

    // Add "Root" option for top level
    if (level == 0) {
      widgets.add(
        RadioListTile<String?>(
          value: null,
          groupValue: selectedFolderId,
          onChanged: (String? value) {
            setState(() {
              selectedFolderId = value;
            });
          },
          title: const Text('Root'),
          subtitle: const Text('Top level'),
        ),
      );
    }

    final subfolders =
        folders.where((folder) => folder.parentId == parentId).toList();

    // Show folders
    for (var folder in subfolders) {
      widgets.add(
        Container(
          margin: EdgeInsets.only(left: level * 20.0),
          child: RadioListTile<String?>(
            value: folder.id,
            groupValue: selectedFolderId,
            onChanged: (String? value) {
              setState(() {
                selectedFolderId = value;
              });
            },
            title: Text(folder.name),
            subtitle: Text(_getFolderInfo(folder)),
            secondary: Icon(
              Icons.folder,
              color: folder.color,
            ),
          ),
        ),
      );

      // Recursively show subfolders
      widgets.addAll(_buildFolderList(folders, folder.id, level + 1));
    }

    return widgets;
  }

  String _getFolderInfo(DictionaryFolder folder) {
    final appState = context.read<ChameleonGUIState>();
    final dictionaries =
        appState.sharedPreferencesProvider.getDictionariesInFolder(folder.id);
    final subfolders = appState.sharedPreferencesProvider
        .getDictionaryFolders()
        .where((f) => f.parentId == folder.id)
        .length;

    String info = '${dictionaries.length} dictionaries';
    if (subfolders > 0) {
      info += ', $subfolders subfolders';
    }
    return info;
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final appState = context.watch<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getDictionaryFolders();

    return AlertDialog(
      title: Text(localizations.move_to_folder),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: SingleChildScrollView(
          child: Column(
            children: _buildFolderList(folders, null, 0),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () {
            appState.sharedPreferencesProvider
                .moveDictionaryToFolder(widget.dictionary.id, selectedFolderId);
            Navigator.pop(context);
          },
          child: Text(localizations.ok),
        ),
      ],
    );
  }
}
