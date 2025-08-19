import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class MoveCardToFolderMenu extends StatefulWidget {
  final CardSave card;
  
  const MoveCardToFolderMenu({super.key, required this.card});

  @override
  MoveCardToFolderMenuState createState() => MoveCardToFolderMenuState();
}

class MoveCardToFolderMenuState extends State<MoveCardToFolderMenu> {
  String? selectedFolderId;

  @override
  void initState() {
    super.initState();
    selectedFolderId = widget.card.folderId;
  }

  Widget _buildFolderTree(String? parentId, {int indent = 0}) {
    var appState = context.read<ChameleonGUIState>();
    var folders = appState.sharedPreferencesProvider.getSubfolders(parentId);
    var localizations = AppLocalizations.of(context)!;

    return Column(
      children: [
        // Add "Root" option for top level
        if (parentId == null) ...[
          Container(
            margin: EdgeInsets.only(left: indent * 16.0),
            child: RadioListTile<String?>(
              title: Text(localizations.root_folder),
              subtitle: Text(localizations.no_folder),
              value: null,
              groupValue: selectedFolderId,
              onChanged: (String? value) {
                setState(() {
                  selectedFolderId = value;
                });
              },
            ),
          ),
          const Divider(),
        ],
        
        // Show folders
        ...folders.map((folder) => Container(
              margin: EdgeInsets.only(left: indent * 16.0),
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: Text(folder.name),
                    subtitle: Text('${appState.sharedPreferencesProvider.getCardsInFolder(folder.id).length} ${localizations.cards.toLowerCase()}'),
                    value: folder.id,
                    groupValue: selectedFolderId,
                    onChanged: (String? value) {
                      setState(() {
                        selectedFolderId = value;
                      });
                    },
                    secondary: Icon(Icons.folder, color: folder.color),
                  ),
                  // Recursively show subfolders
                  _buildFolderTree(folder.id, indent: indent + 1),
                ],
              ),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.move_to_folder),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${localizations.card}: ${widget.card.name.isEmpty ? widget.card.uid : widget.card.name}'),
              const SizedBox(height: 16),
              _buildFolderTree(null),
            ],
          ),
        ),
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
            var appState = context.read<ChameleonGUIState>();
            appState.sharedPreferencesProvider.moveCardToFolder(
              widget.card.id,
              selectedFolderId,
            );
            appState.changesMade();
            Navigator.of(context).pop();
          },
          child: Text(localizations.save),
        ),
      ],
    );
  }
}
