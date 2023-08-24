import 'package:chameleonultragui/gui/component/developer_list.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/helpers/open_collective.dart';
import 'package:chameleonultragui/main.dart';
import 'package:url_launcher/url_launcher.dart';

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
        title: const Text('Settings'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            const SizedBox(height: 10),
            const Text("Sidebar Expansion:"),
            const SizedBox(height: 8),
            ToggleButtonsWrapper(
                items: const ['Expand', 'Auto', 'Retract'],
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
            const Text("Theme:"),
            const SizedBox(height: 8),
            ToggleButtonsWrapper(
                items: const ['System', 'Light', 'Dark'],
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
                      title: const Text('Restart Required'),
                      content: const Center(
                        child: Text('Changes will take effect after a restart',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context, 'OK'),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }),
            const SizedBox(height: 10),
            const Text("Color scheme:"),
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
                    title: const Text('Restart Required'),
                    content: const Center(
                      child: Text('Changes will take effect after a restart',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'OK'),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text("Default"),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text("Purple"),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text("Blue"),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text("Green"),
                ),
                DropdownMenuItem(
                  value: 4,
                  child: Text("Indigo"),
                ),
                DropdownMenuItem(
                  value: 5,
                  child: Text("Lime"),
                ),
                DropdownMenuItem(
                  value: 6,
                  child: Text("Red"),
                ),
                DropdownMenuItem(
                  value: 7,
                  child: Text("Yellow"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('About'),
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
                              const Text(
                                  'A Tool to graphically manage and configure your Chameleon Ultra, written in Flutter and running on Desktop and Mobile.'),
                              const SizedBox(height: 10),
                              const Text('Version:'),
                              Text(
                                  '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              const Text('Developed by:'),
                              const SizedBox(height: 10),
                              DeveloperList(avatars: developers),
                              const SizedBox(height: 10),
                              const Text('License:'),
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
                              const Text(
                                  "Thanks to everyone who supports us on Open Collective!"),
                              const SizedBox(height: 10),
                              Text(names,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              const Text('Code contributors:'),
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
              child: const Text('About'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('Debug mode?'),
                  content: Text(
                      'Are you sure you want to ${appState.sharedPreferencesProvider.getDeveloperMode() ? "deactivate" : "activate"} debug mode? It is created specifically for developers to test specific app functions on UNSUPPORTED platforms'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'Cancel'),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        appState.devMode = true;
                        if (appState.sharedPreferencesProvider
                            .getDeveloperMode()) {
                          appState.sharedPreferencesProvider
                              .setDeveloperMode(false);
                        } else {
                          appState.sharedPreferencesProvider
                              .setDeveloperMode(true);
                        }
                        appState.changesMade();
                        Navigator.pop(context, 'OK');
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: const Text('Activate debug mode'),
            )
          ],
        ),
      ),
    );
  }
}
