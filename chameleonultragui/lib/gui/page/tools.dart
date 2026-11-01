import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/desfire_reader.dart';
import 'package:chameleonultragui/gui/menu/tools/dictionary_download.dart';
import 'package:chameleonultragui/gui/menu/tools/emv_scan.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/lf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/t55xx_password_cleaner.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:chameleonultragui/gui/component/element_button.dart';
import 'package:provider/provider.dart';

class ToolItem {
  final String name;
  final String description;
  final IconData icon;
  final bool isDeviceRequired;
  final bool showWipBadge;
  final Widget? onPressed;
  // Wire command ID (ChameleonCommand.*.value) that must be present in
  // getDeviceCapabilities() for this tool to show at all. Null = always
  // shown. Used to hide fork-only tools (Phreakbyte additions) from GUIs
  // talking to stock firmware that doesn't implement them.
  final int? requiredCapability;

  ToolItem({
    required this.name,
    required this.description,
    required this.icon,
    this.isDeviceRequired = false,
    this.showWipBadge = false,
    this.onPressed,
    this.requiredCapability,
  });
}

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  // Mirrors HomePageState.areCapabilitiesSupported()'s use of
  // getDeviceCapabilities(): not cached, re-queried on every build like
  // the rest of this app's device-state reads. Empty when disconnected
  // or on error, so capability-gated tools stay hidden rather than risk
  // showing a tool the firmware can't actually run.
  Future<List<int>> _getCapabilities(ChameleonGUIState appState) async {
    if (appState.connector == null || !appState.connector!.connected) {
      return [];
    }
    try {
      return await appState.communicator!.getDeviceCapabilities();
    } catch (_) {
      return [];
    }
  }

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
          name: localizations.t55xx_password_cleaner,
          description: localizations.t55xx_password_cleaner_description,
          icon: Icons.password,
          onPressed: const T55XXPasswordCleanerMenu(),
          isDeviceRequired: true),
      ToolItem(
          name: localizations.lf_sniffing,
          description: localizations.lf_sniffing_description,
          icon: Icons.graphic_eq,
          onPressed: const LfSniffingMenu()),
      ToolItem(
          name: localizations.hf_sniffing,
          description: localizations.hf_sniffing_description,
          icon: Icons.radar,
          onPressed: const HfSniffingMenu()),
      ToolItem(
          name: localizations.mifare_classic_gen4,
          description: localizations.mifare_classic_gen4_description,
          icon: Icons.settings,
          isDeviceRequired: true),
      ToolItem(
          name: localizations.desfire_title,
          description: localizations.desfire_description,
          icon: Icons.credit_card,
          onPressed: const DesfireReaderMenu(),
          isDeviceRequired: true,
          requiredCapability: ChameleonCommand.desfireGetInfo.value),
      ToolItem(
          name: localizations.emv_scan_title,
          description: localizations.emv_scan_description,
          icon: Icons.payment,
          onPressed: const EmvScanMenu(),
          isDeviceRequired: true,
          requiredCapability: ChameleonCommand.hf14a4EmvScan.value),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.tools),
      ),
      body: FutureBuilder<List<int>>(
        future: _getCapabilities(appState),
        builder: (context, snapshot) {
          final capabilities = snapshot.data ?? const <int>[];
          final visibleTools = tools
              .where((t) =>
                  t.requiredCapability == null ||
                  capabilities.contains(t.requiredCapability))
              .toList();

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AlignedGridView.count(
                clipBehavior: Clip.antiAlias,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount:
                    MediaQuery.of(context).size.width >= 700 ? 2 : 1,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                itemCount: visibleTools.length,
                shrinkWrap: true,
                itemBuilder: (BuildContext context, int index) {
                  final tool = visibleTools[index];
                  final disconnected =
                      tool.isDeviceRequired && !appState.connector!.connected;
                  return Stack(
                    children: [
                      ElementButton(
                          icon: tool.icon,
                          iconColor: Theme.of(context).colorScheme.primary,
                          firstLine: tool.name,
                          secondLine: tool.description,
                          itemIndex: index,
                          maxLineLines: 3,
                          onPressed: tool.onPressed != null &&
                                  (!tool.isDeviceRequired ||
                                      appState.connector!.connected)
                              ? () {
                                  showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return tool.onPressed!;
                                      });
                                }
                              : null,
                          children: []),
                      if (tool.showWipBadge || tool.onPressed == null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              localizations.wip,
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.inversePrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (disconnected)
                        Positioned(
                          top: tool.showWipBadge || tool.onPressed == null
                              ? 32
                              : 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              localizations.device_required,
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.inversePrimary,
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
          );
        },
      ),
    );
  }
}
