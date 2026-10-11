import 'package:chameleonultragui/gui/menu/dialogs/settings_actions.dart';
import 'package:chameleonultragui/gui/menu/pages/changelog_view.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// App settings as a grouped list. Same preferences and dialogs as the desktop
/// settings page, minus the sidebar option, which has no meaning on phones.
class MobileSettingsPage extends StatelessWidget {
  const MobileSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final prefs = appState.sharedPreferencesProvider;
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget header(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    Widget switchTile(String title, bool value, void Function(bool) onChanged) {
      return SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: (v) {
          onChanged(v);
          appState.changesMade();
        },
      );
    }

    // Switches that ask for confirmation before flipping.
    Widget confirmedSwitchTile(
      String title,
      bool value,
      void Function(BuildContext) confirm,
    ) {
      return SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: (_) => confirm(context),
      );
    }

    final colors = [
      localizations.def,
      localizations.purple,
      localizations.blue,
      localizations.green,
      localizations.indigo,
      localizations.lime,
      localizations.red,
      localizations.yellow,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(localizations.settings)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
        ),
        children: [
          header(localizations.theme),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(localizations.system),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(localizations.light),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(localizations.dark),
                ),
              ],
              selected: {prefs.getTheme()},
              onSelectionChanged: (selection) {
                prefs.setTheme(selection.first);
                appState.changesMade();
              },
            ),
          ),
          ListTile(
            minTileHeight: 56,
            title: Text(localizations.color_scheme),
            trailing: DropdownButton<int>(
              value: prefs.getThemeColorIndex(),
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                prefs.setThemeColor(value ?? 0);
                appState.changesMade();
              },
              items: [
                for (int i = 0; i < colors.length; i++)
                  DropdownMenuItem(value: i, child: Text(colors[i])),
              ],
            ),
          ),
          ListTile(
            minTileHeight: 56,
            title: Text(localizations.language),
            trailing: DropdownButton<String>(
              value: prefs.getLocaleString(),
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                prefs.setLocale(Locale(value ?? 'en'));
                appState.changesMade();
              },
              items: AppLocalizations.supportedLocales.map((locale) {
                return DropdownMenuItem(
                  value: locale.toLanguageTag(),
                  child: Text(lookupAppLocalizations(locale).language_name),
                );
              }).toList(),
            ),
          ),
          header(localizations.connect),
          switchTile(
            localizations.auto_scan_devices,
            prefs.getAutoScanEnabled(),
            prefs.setAutoScanEnabled,
          ),
          switchTile(
            localizations.auto_connect_first_device,
            prefs.getAutoConnectFirstFoundDevice(),
            prefs.setAutoConnectFirstFoundDevice,
          ),
          switchTile(
            localizations.confirm_deletions,
            prefs.getConfirmDelete(),
            prefs.setConfirmDelete,
          ),
          header(localizations.other),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.upload),
            title: Text(localizations.export_settings),
            onTap: () => showExportSettingsDialog(context),
          ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.download),
            title: Text(localizations.import_settings),
            onTap: () => showImportSettingsDialog(context),
          ),
          header(localizations.about),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.info_outline),
            title: Text(localizations.about),
            onTap: () => showAboutAppDialog(context),
          ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.description_outlined),
            title: Text(localizations.licenses),
            onTap: () => showLicenses(context),
          ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.history),
            title: Text(localizations.changelog),
            onTap: () => showDialog<String>(
              context: context,
              builder: (_) => const ChangelogView(),
            ),
          ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.translate),
            title: Text(localizations.help_translate),
            onTap: () => launchUrl(
              Uri.parse('https://crowdin.com/project/chameleonultragui'),
            ),
          ),
          header(localizations.advanced),
          confirmedSwitchTile(
            localizations.emulate_device,
            prefs.isEmulatedChameleon(),
            toggleEmulatedDeviceDialog,
          ),
          confirmedSwitchTile(
            localizations.debug_mode,
            prefs.isDebugMode(),
            toggleDebugModeDialog,
          ),
        ],
      ),
    );
  }
}
