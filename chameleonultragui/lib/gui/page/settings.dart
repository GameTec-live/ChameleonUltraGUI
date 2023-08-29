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
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.settings),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            const SizedBox(height: 10),
            Text(localizations.sidebar_expansion,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            ToggleButtonsWrapper(
                items: [localizations.expand, localizations.auto, localizations.retract
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
              localizations.theme,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            ToggleButtonsWrapper(
                items: [localizations.system, localizations.light, localizations.dark],
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
                      title: Text(localizations.restart_required),
                      content: Center(
                        child: Text(localizations.take_effects,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context, localizations.ok),
                          child: Text(localizations.ok),
                        ),
                        TextButton(
                          onPressed: () => SystemChannels.platform
                              .invokeMethod('SystemNavigator.pop'),
                          child: Text(localizations.restart_now),
                        ),
                      ],
                    ),
                  );
                }),
            const SizedBox(height: 10),
            Text(
              localizations.color_scheme,
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
                    title: Text(localizations.restart_required),
                    content: Center(
                      child: Text(localizations.take_effects,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, localizations.ok),
                        child: Text(localizations.ok),
                      ),
                      TextButton(
                        onPressed: () => SystemChannels.platform
                            .invokeMethod('SystemNavigator.pop'),
                        child: Text(localizations.restart_now),
                      ),
                    ],
                  ),
                );
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
            Text(localizations.language, style: const TextStyle(fontWeight: FontWeight.bold),),
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
                    title: Text(localizations.restart_required),
                    content: Center(
                      child: Text(localizations.take_effects,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, localizations.ok),
                        child: Text(localizations.ok),
                      ),
                      TextButton(
                        onPressed: () => SystemChannels.platform
                            .invokeMethod('SystemNavigator.pop'),
                        child: Text(localizations.restart_now),
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
                  title: Text(localizations.about),
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
                                  localizations.about_text),
                              const SizedBox(height: 10),
                              Text('${localizations.version}:'),
                              Text(
                                  '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Text('${localizations.developed_by}:'),
                              const SizedBox(height: 10),
                              DeveloperList(avatars: developers),
                              const SizedBox(height: 10),
                              Text('${localizations.license}:'),
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
                                  localizations.thanks_for_support),
                              const SizedBox(height: 10),
                              Text(names,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Text('${localizations.code_contributors}:'),
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
                      onPressed: () => Navigator.pop(context, localizations.ok),
                      child: Text(localizations.ok),
                    ),
                  ],
                ),
              ),
              child: Text(localizations.about),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: Text(localizations.debug_mode),
                  content: Text(
                      localizations.debug_mode_confirmation(
                          appState.sharedPreferencesProvider.isDebugMode()
                              ? localizations.deactivate.toLowerCase()
                              : localizations.activate.toLowerCase())),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, localizations.cancel),
                      child: Text(localizations.cancel),
                    ),
                    TextButton(
                      onPressed: () {
                        appState.sharedPreferencesProvider.setDebugMode(
                            !appState.sharedPreferencesProvider.isDebugMode());
                        appState.changesMade();
                        Navigator.pop(context, localizations.ok);
                      },
                      child: Text(localizations.ok),
                    ),
                  ],
                ),
              ),
              child: Text("${appState.sharedPreferencesProvider.isDebugMode() ? localizations.deactivate : localizations.activate} ${localizations.debug_mode.toLowerCase()}"),
            )
          ],
        ),
      ),
    );
  }
}
