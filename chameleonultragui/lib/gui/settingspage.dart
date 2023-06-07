import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:toggle_switch/toggle_switch.dart';
import 'package:logger/logger.dart';
import '../main.dart';

class SettingsMainPage extends StatelessWidget {
  /* Todo list:
  Think of useful settings that users might want to change
  Make sure we fix (context as Element).reassemble(); under the switch. It's terrible. 
  */
  const SettingsMainPage({super.key});

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
            Switch(
              value: appState.switchOn,
              activeColor: Colors.blue,
              activeTrackColor: Colors.green,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.red,
              onChanged: (bool value) {
                // This is called when the user toggles the switch.
                Logger log = Logger();
                log.d('Switch toggled');
                //appState.toggleswitch();
                appState.switchOn = !appState.switchOn;
                //(context as Element).reassemble();
                appState.changesMade();
              },
            ),
            const SizedBox(height: 10),
            const Text("Sidebar Expansion:"),
            ToggleSwitch(
              minWidth: 90.0,
              cornerRadius: 20.0,
              activeFgColor: Colors.white,
              inactiveBgColor: Colors.grey,
              inactiveFgColor: Colors.white,
              initialLabelIndex: appState.sharedPreferencesProvider.getSideBarExpandedIndex(),
              totalSwitches: 3,
              labels: const ['Expand', 'automatic', 'retract'],
              radiusStyle: true,
              onToggle: (index) {
                if (index == 0) {
                  appState.sharedPreferencesProvider.setSideBarExpanded(true);
                  appState.sharedPreferencesProvider.setSideBarAutoExpansion(false);
                } else if (index == 2) {
                  appState.sharedPreferencesProvider.setSideBarExpanded(false);
                  appState.sharedPreferencesProvider.setSideBarAutoExpansion(false);
                } else {
                  appState.sharedPreferencesProvider.setSideBarAutoExpansion(true);
                }
                appState.sharedPreferencesProvider.setSideBarExpandedIndex(index ?? 1);
                appState.changesMade();
              },
            ),
            const SizedBox(height: 10),
            const Text("Theme:"),
            ToggleSwitch(
              minWidth: 90.0,
              cornerRadius: 20.0,
              activeFgColor: Colors.white,
              inactiveBgColor: Colors.grey,
              inactiveFgColor: Colors.white,
              initialLabelIndex: appState.sharedPreferencesProvider.getTheme() == ThemeMode.system ? 0 : appState.sharedPreferencesProvider.getTheme() == ThemeMode.dark ? 2 : 1,
              totalSwitches: 3,
              labels: const ['System', 'Light', 'Dark'],
              radiusStyle: true,
              onToggle: (index) {
                if (index == 0) {
                  appState.sharedPreferencesProvider.setTheme(ThemeMode.system);
                } else if (index == 2) {
                  appState.sharedPreferencesProvider.setTheme(ThemeMode.dark);
                } else {
                  appState.sharedPreferencesProvider.setTheme(ThemeMode.light);
                }
                appState.changesMade();
                showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: const Text('Restart Required'),
                    content: const Center(child:  Text('Changes will take effect after a restart', style: TextStyle(fontWeight: FontWeight.bold)),),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'OK'),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('About'),
                  content: const Center(
                    child:  Column(
                      children: [
                        Text('Chameleon Ultra GUI', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('A Tool to graphically manage and configure your Chameleon Ultra, written in Flutter and running on Desktop and Mobile.'),
                        SizedBox(height: 10),
                        Text('Version:'),
                        Text('UNRELEASED', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 10),
                        Text('Developed by:'),
                        Text('Foxushka, Akisame and GameTec_live', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 10),
                        Text('License:'),
                        Text('GPLV3', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 10),
                        Text('https://github.com/GameTec-live/ChameleonUltraGUI'),
                      ],
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
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('Developer mode?'),
                  content: const Text(
                      'Are you sure you want to activate developer mode?'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'Cancel'),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'OK'),
                      child: const Text('OK'),
                      // Never gonna give you up! Never gonna let you down!
                    ),
                  ],
                ),
              ),
              child: const Text('Activate developer mode'),
            )
          ],
        ),
      ),
    );
  }
}