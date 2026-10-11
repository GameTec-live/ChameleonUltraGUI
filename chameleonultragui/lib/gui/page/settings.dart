import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/gui/menu/dialogs/settings_actions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chameleonultragui/gui/menu/pages/changelog_view.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  SettingsMainPageState createState() => SettingsMainPageState();
}

class SettingsMainPageState extends State<SettingsMainPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.settings),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              Text(localizations.sidebar_expansion,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                  items: [
                    localizations.expand,
                    localizations.auto,
                    localizations.retract
                  ],
                  selectedValue: appState.sharedPreferencesProvider
                      .getSideBarExpandedIndex(),
                  onChange: (int index) async {
                    if (index == 0) {
                      appState.sharedPreferencesProvider
                          .setSideBarExpanded(true);
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(false);
                    } else if (index == 2) {
                      appState.sharedPreferencesProvider
                          .setSideBarExpanded(false);
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(false);
                    } else {
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(true);
                    }
                    appState.sharedPreferencesProvider
                        .setSideBarExpandedIndex(index);
                    appState.changesMade();

                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => updateNavigationRailWidth(context));
                  }),
              const SizedBox(height: 10),
              Text(
                localizations.theme,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                  items: [
                    localizations.system,
                    localizations.light,
                    localizations.dark
                  ],
                  selectedValue:
                      appState.sharedPreferencesProvider.getTheme().index,
                  onChange: (int index) async {
                    appState.sharedPreferencesProvider
                        .setTheme(ThemeMode.values[index]);
                    appState.changesMade();
                  }),
              const SizedBox(height: 10),
              Text(
                localizations.color_scheme,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              DropdownButton(
                value: appState.sharedPreferencesProvider.getThemeColorIndex(),
                icon: const Icon(Icons.arrow_downward),
                elevation: 16,
                onChanged: (value) {
                  appState.sharedPreferencesProvider.setThemeColor(value ?? 0);
                  appState.changesMade();
                },
                items: [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(localizations.def),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(localizations.purple),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(localizations.blue),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text(localizations.green),
                  ),
                  DropdownMenuItem(
                    value: 4,
                    child: Text(localizations.indigo),
                  ),
                  DropdownMenuItem(
                    value: 5,
                    child: Text(localizations.lime),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text(localizations.red),
                  ),
                  DropdownMenuItem(
                    value: 7,
                    child: Text(localizations.yellow),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                localizations.language,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: DropdownButton(
                  value: appState.sharedPreferencesProvider.getLocaleString(),
                  onChanged: (value) {
                    appState.sharedPreferencesProvider
                        .setLocale(Locale(value ?? 'en'));
                    appState.changesMade();
                  },
                  items: AppLocalizations.supportedLocales.map((locale) {
                    final localeLocalizations = lookupAppLocalizations(locale);
                    return DropdownMenuItem(
                        value: locale.toLanguageTag(),
                        child: Text(localeLocalizations.language_name));
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.auto_scan_devices,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value:
                        appState.sharedPreferencesProvider.getAutoScanEnabled(),
                    onChanged: (value) async {
                      appState.sharedPreferencesProvider
                          .setAutoScanEnabled(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.auto_connect_first_device,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value: appState.sharedPreferencesProvider
                        .getAutoConnectFirstFoundDevice(),
                    onChanged: (value) async {
                      appState.sharedPreferencesProvider
                          .setAutoConnectFirstFoundDevice(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.confirm_deletions,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value:
                        appState.sharedPreferencesProvider.getConfirmDelete(),
                    onChanged: (value) async {
                      appState.sharedPreferencesProvider
                          .setConfirmDelete(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TextButton(
                    onPressed: () => showExportSettingsDialog(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppLocalizations.of(context)!.export_settings),
                        const Icon(Icons.upload)
                      ],
                    )),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TextButton(
                  onPressed: () => showImportSettingsDialog(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppLocalizations.of(context)!.import_settings),
                      const Icon(Icons.download),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showAboutAppDialog(context),
                child: Text(localizations.about),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showLicenses(context),
                child: Text(localizations.licenses),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => const ChangelogView(),
                ),
                child: Text(localizations.changelog),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  await launchUrl(Uri.parse(
                      'https://crowdin.com/project/chameleonultragui'));
                },
                child: Text(localizations.help_translate),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => toggleEmulatedDeviceDialog(context),
                child: Text(
                    "${appState.sharedPreferencesProvider.isEmulatedChameleon() ? localizations.deactivate : localizations.activate} ${localizations.emulate_device.toLowerCase()}"),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => toggleDebugModeDialog(context),
                child: Text(
                    "${appState.sharedPreferencesProvider.isDebugMode() ? localizations.deactivate : localizations.activate} ${localizations.debug_mode.toLowerCase()}"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
