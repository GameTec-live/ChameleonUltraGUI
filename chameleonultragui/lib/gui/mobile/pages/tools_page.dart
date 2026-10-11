import 'package:chameleonultragui/gui/menu/dialogs/chameleon_settings.dart';
import 'package:chameleonultragui/gui/mobile/pages/settings_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/writer_page.dart';
import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// The "More" tab: everything that doesn't fit the primary destinations.
class MobileToolsPage extends StatelessWidget {
  const MobileToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final connected = appState.connector!.connected;
    final debug = appState.sharedPreferencesProvider.isDebugMode();
    final tools = getToolItems(localizations);

    void push(Widget page) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page));

    Widget tile({
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
      bool deviceRequired = false,
      bool wip = false,
    }) {
      final needsDevice = deviceRequired && !connected;
      final details = [
        ?subtitle,
        if (wip) localizations.wip,
        if (needsDevice) localizations.device_required,
      ].join(' · ');
      return ListTile(
        minTileHeight: 64,
        leading: Icon(icon),
        title: Text(title),
        subtitle: details.isEmpty
            ? null
            : Text(details, maxLines: 3, overflow: TextOverflow.ellipsis),
        enabled: onTap != null && !needsDevice,
        onTap: onTap,
        trailing: onTap != null && !needsDevice
            ? const Icon(Icons.chevron_right)
            : null,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(localizations.mobile_nav_more)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          MobileSectionHeader(localizations.cards),
          tile(
            icon: Icons.system_update_alt,
            title: localizations.write_card,
            subtitle: localizations.select_saved_card_to_write,
            deviceRequired: true,
            onTap: () => push(const MobileWriterPage()),
          ),
          tile(
            icon: Icons.key,
            title: localizations.dictionaries,
            onTap: () => push(
              const SavedCardsPage(section: SavedCardsSection.dictionaries),
            ),
          ),
          MobileSectionHeader(localizations.tools),
          for (final tool in tools)
            tile(
              icon: tool.icon,
              title: tool.name,
              subtitle: tool.description,
              deviceRequired: tool.isDeviceRequired,
              wip: tool.onPressed == null || tool.showWipBadge,
              onTap: tool.onPressed == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => tool.onPressed!,
                    ),
            ),
          MobileSectionHeader(localizations.device_settings),
          tile(
            icon: Icons.memory,
            title: localizations.firmware_management,
            subtitle: localizations.device_settings,
            deviceRequired: true,
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const ChameleonSettings(),
            ),
          ),
          MobileSectionHeader(localizations.settings),
          tile(
            icon: Icons.settings,
            title: localizations.settings,
            onTap: () => push(const MobileSettingsPage()),
          ),
          if (debug)
            tile(
              icon: Icons.bug_report,
              title: localizations.debug,
              onTap: () => push(const DebugPage()),
            ),
        ],
      ),
    );
  }
}
