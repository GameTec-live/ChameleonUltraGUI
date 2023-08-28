import 'package:chameleonultragui/gui/component/developer_list.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/helpers/open_collective.dart';
import 'package:chameleonultragui/main.dart';
import 'package:url_launcher/url_launcher.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({Key? key}) : super(key: key);

  @override
  SettingsMainPageState createState() => SettingsMainPageState();
}

class SettingsMainPageState extends State<SettingsMainPage> {
  @override
  void initState() {
    super.initState();
  }

  Future<(String, List<Map<String, String>>, PackageInfo)>
      getFutureData() async {
    return (
      await fetchOCnames(),
      await fetchContributors(),
      await PackageInfo.fromPlatform()
    );
  }

  Future<String> fetchOCnames() async {
    final List<String> names = await fetchOpenCollectiveContributors();
    String finalNames = "";
    for (String name in names) {
      finalNames += "$name, ";
    }
    return finalNames.substring(0, finalNames.length - 2);
  }

  Future<List<Map<String, String>>> fetchContributors() async {
    return await fetchGitHubContributors();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            const SizedBox(height: 10),
            Text(AppLocalizations.of(context)!.sidebar_expansion,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            ToggleButtonsWrapper(
                items: [AppLocalizations.of(context)!.expand, AppLocalizations.of(context)!.auto, AppLocalizations.of(context)!.retract
                ],
                selectedValue: appState.sharedPreferencesProvider
                    .getSideBarExpandedIndex(),
                onChange: (int index) async {
                  if (index == 0) {
                    appState.sharedPreferencesProvider.setSideBarExpanded(true);
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
                }),
            const SizedBox(height: 10),
                        Text(
              AppLocalizations.of(context)!.theme,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            ToggleButtonsWrapper(
                items: [AppLocalizations.of(context)!.system, AppLocalizations.of(context)!.light, AppLocalizations.of(context)!.dark],
                selectedValue: appState.sharedPreferencesProvider.getTheme() ==
                        ThemeMode.system
                    ? 0
                    : appState.sharedPreferencesProvider.getTheme() ==
                            ThemeMode.dark
                        ? 2
                        : 1,
                onChange: (int index) async {
                  if (index == 0) {
                    appState.sharedPreferencesProvider
                        .setTheme(ThemeMode.system);
                  } else if (index == 2) {
                    appState.sharedPreferencesProvider.setTheme(ThemeMode.dark);
                  } else {
                    appState.sharedPreferencesProvider
                        .setTheme(ThemeMode.light);
                  }
                  appState.changesMade();
                  showDialog<String>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: Text(AppLocalizations.of(context)!.restart_required),
                      content: Center(
                        child: Text(AppLocalizations.of(context)!.take_effects,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context, AppLocalizations.of(context)!.ok),
                          child: Text(AppLocalizations.of(context)!.ok),
                        ),
                        TextButton(
                          onPressed: () => SystemNavigator.pop(),
                          child: Text(AppLocalizations.of(context)!.restart_now),
                        ),
                      ],
                    ),
                  );
                }),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context)!.color_scheme,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            DropdownButton(
              value: appState.sharedPreferencesProvider.sharedPreferences
                      .getInt('app_theme_color') ??
                  0,
              icon: const Icon(Icons.arrow_downward),
              elevation: 16,
              onChanged: (value) {
                appState.sharedPreferencesProvider.setThemeColor(value ?? 0);
                appState.changesMade();
                showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(AppLocalizations.of(context)!.restart_required),
                    content: Center(
                      child: Text(AppLocalizations.of(context)!.take_effects,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'OK'),
                        child: Text(AppLocalizations.of(context)!.ok),
                      ),
                      TextButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: Text(AppLocalizations.of(context)!.restart_now),
                      ),
                    ],
                  ),
                );
              },
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(AppLocalizations.of(context)!.def),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text(AppLocalizations.of(context)!.purple),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text(AppLocalizations.of(context)!.blue),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text(AppLocalizations.of(context)!.green),
                ),
                DropdownMenuItem(
                  value: 4,
                  child: Text(AppLocalizations.of(context)!.indigo),
                ),
                DropdownMenuItem(
                  value: 5,
                  child: Text(AppLocalizations.of(context)!.lime),
                ),
                DropdownMenuItem(
                  value: 6,
                  child: Text(AppLocalizations.of(context)!.red),
                ),
                DropdownMenuItem(
                  value: 7,
                  child: Text(AppLocalizations.of(context)!.yellow),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(AppLocalizations.of(context)!.language, style: const TextStyle(fontWeight: FontWeight.bold),),
            const SizedBox(height: 5),
            DropdownButton(
              value: appState.sharedPreferencesProvider.sharedPreferences
                      .getString('locale') ??
                  'en',
              onChanged: (value) {
                appState.sharedPreferencesProvider
                    .setLocale(Locale(value ?? 'en'));
                appState.changesMade();
                showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(AppLocalizations.of(context)!.restart_required),
                    content: Center(
                      child: Text(AppLocalizations.of(context)!.take_effects,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, AppLocalizations.of(context)!.ok),
                        child: Text(AppLocalizations.of(context)!.ok),
                      ),
                      TextButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: Text(AppLocalizations.of(context)!.restart_now),
                      ),
                    ],
                  ),
                );
              },
              items: AppLocalizations.supportedLocales.map((locale) {
                return DropdownMenuItem(
                  value: locale.languageCode,
                  child: Text(appState.sharedPreferencesProvider.getFlag(locale)),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: Text(AppLocalizations.of(context)!.about),
                  content: Center(
                    child: FutureBuilder(
                      future: getFutureData(),
                      builder: (BuildContext context, AsyncSnapshot snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        } else if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        } else {
                          final (names, contributors, packageInfo) =
                              snapshot.data;
                          return SingleChildScrollView(
                              child: Column(
                            children: [
                              const Text('Chameleon Ultra GUI',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                  AppLocalizations.of(context)!.about_text),
                              const SizedBox(height: 10),
                              Text('${AppLocalizations.of(context)!.version}:'),
                              Text(
                                  '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Text('${AppLocalizations.of(context)!.developed_by}:'),
                              const SizedBox(height: 10),
                              DeveloperList(avatars: developers),
                              const SizedBox(height: 10),
                              Text('${AppLocalizations.of(context)!.license}:'),
                              const Text('GNU General Public License v3.0',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              GestureDetector(
                                  onTap: () async {
                                    await launchUrl(Uri.parse(
                                        'https://github.com/GameTec-live/ChameleonUltraGUI'));
                                  },
                                  child: const Text(
                                      'https://github.com/GameTec-live/ChameleonUltraGUI')),
                              const SizedBox(height: 30),
                              Text(
                                  AppLocalizations.of(context)!.thanks_for_support),
                              const SizedBox(height: 10),
                              Text(names,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Text('${AppLocalizations.of(context)!.code_contributors}:'),
                              const SizedBox(height: 10),
                              DeveloperList(avatars: contributors),
                            ],
                          ));
                        }
                      },
                    ),
                  ),
                  actions: <Widget>[
                    /* TextButton(
                            onPressed: () => Navigator.pop(context, 'Cancel'),
                            child: const Text('Cancel'),
                          ), */ // A Cancel button on an about widget??
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'OK'),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: Text(AppLocalizations.of(context)!.about),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: Text(AppLocalizations.of(context)!.debug_mode),
                  content: Text(
                      AppLocalizations.of(context)!.debug_mode_confirmation(
                          appState.sharedPreferencesProvider.isDebugMode()
                              ? AppLocalizations.of(context)!.deactivate.toLowerCase()
                              : AppLocalizations.of(context)!.activate.toLowerCase())),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, AppLocalizations.of(context)!.cancel),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    TextButton(
                      onPressed: () {
                        appState.sharedPreferencesProvider.setDebugMode(
                            !appState.sharedPreferencesProvider.isDebugMode());
                        appState.changesMade();
                        Navigator.pop(context, AppLocalizations.of(context)!.ok);
                      },
                      child: Text(AppLocalizations.of(context)!.ok),
                    ),
                  ],
                ),
              ),
              child: Text("${appState.sharedPreferencesProvider.isDebugMode() ? AppLocalizations.of(context)!.deactivate : AppLocalizations.of(context)!.activate} ${AppLocalizations.of(context)!.debug_mode.toLowerCase()}"),
            )
          ],
        ),
      ),
    );
  }
}
