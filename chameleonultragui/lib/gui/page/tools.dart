import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/dictionary_download.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:chameleonultragui/gui/component/saved_card.dart';
import 'package:provider/provider.dart';

class ToolItem {
  final String name;
  final String description;
  final IconData icon;
  final bool isWIP;
  final bool isDeviceRequired;
  final Widget? onPressed;

  ToolItem({
    required this.name,
    required this.description,
    required this.icon,
    this.isWIP = false,
    this.isDeviceRequired = false,
    this.onPressed,
  });
}

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    List<ToolItem> tools = [
      ToolItem(
          name: localizations.dictionary_download,
          description: localizations.dictionary_download_description,
          icon: Icons.key,
          onPressed: const DictionaryDownloadMenu()),
      ToolItem(
          name: localizations.mifare_classic_gen4,
          description: localizations.mifare_classic_gen4_description,
          icon: Icons.settings,
          isWIP: true,
          isDeviceRequired: true),
      ToolItem(
          name: localizations.t55xx_password_cleaner,
          description: localizations.t55xx_password_cleaner_description,
          icon: Icons.password,
          isWIP: true,
          isDeviceRequired: true),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.tools),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: AlignedGridView.count(
            clipBehavior: Clip.antiAlias,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 2 : 1,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            itemCount: tools.length,
            shrinkWrap: true,
            itemBuilder: (BuildContext context, int index) {
              final tool = tools[index];
              return Stack(
                children: [
                  SavedCard(
                      icon: tool.icon,
                      iconColor: Theme.of(context).colorScheme.primary,
                      firstLine: tool.name,
                      secondLine: tool.description,
                      itemIndex: index,
                      onPressed: tool.onPressed != null
                          ? () {
                              showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return tool.onPressed!;
                                  });
                            }
                          : null,
                      children: []),
                  if (tool.isWIP)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          localizations.wip,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (tool.isDeviceRequired && !appState.connector!.connected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          localizations.device_required,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
