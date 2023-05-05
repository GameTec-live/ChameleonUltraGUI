import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:serial_communication/serial_communication.dart'; // Android
import 'package:flutter_libserialport/flutter_libserialport.dart'; // Everyone Else
import 'package:toggle_switch/toggle_switch.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  // Root Widget
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Chameleon Ultra GUI', // App Name
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepOrange), // Color Scheme
        ),
        home: const MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  // State
  bool onandroid =
      Platform.isAndroid; // Are we on android? (mostly for serial port)
  var chameleon; // Chameleon Object, connected Chameleon
  bool switchOn = true;
  /*void toggleswitch() {
    setState(() {
      switchOn = !switchOn;
    })
  }
  // This doesn't work because we aren't working stateful
  */
  var _isExpanded =
      true; // I am planning to use this to control the navigation rail expansion.
  bool automaticExpansion = true;
  // maybe via this: https://www.woolha.com/tutorials/flutter-switch-input-widget-example or this https://dev.to/naidanut/adding-expandable-side-bar-using-navigationrail-in-flutter-5ai8
  int? expandedIndex = 1;
  void changesMade() {
    notifyListeners();
  }
}

class MyHomePage extends StatefulWidget {
  // Main Page
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Main Page State, Sidebar visible, Navigation
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    if (appState.onandroid) {
      // Set Chameleon Object
      appState.chameleon = CommmoduleAndroid();
    } else {
      appState.chameleon = CommmodulePC();
    }
    if (appState.automaticExpansion) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState._isExpanded = true;
      } else {
        appState._isExpanded = false;
      }
    }

    Widget page; // Set Page
    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        page = const HomePage();
        break;
      case 1:
        page = const Placeholder();
        break;
      case 2:
        page = const SavedKeysPage();
        break;
      case 3:
        page = const Placeholder();
        break;
      case 4:
        page = const Placeholder();
        break;
      case 5:
        page = SettingsMainPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }
    return LayoutBuilder(// Build Page
        builder: (context, constraints) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                // Sidebar
                extended: appState._isExpanded,
                destinations: const [
                  // Sidebar Items
                  NavigationRailDestination(
                    icon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.widgets),
                    label: Text('Slot Manager'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.auto_awesome_motion_outlined),
                    label: Text('Saved keys'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.wifi),
                    label: Text('Live Read/Write'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.shield),
                    label: Text('Attacks'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    label: Text('Settings'),
                  ),
                ],
                selectedIndex: selectedIndex,
                onDestinationSelected: (value) {
                  setState(() {
                    selectedIndex = value;
                  });
                },
              ),
            ),
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: page,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class HomePage extends StatelessWidget {
  // Home Page
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Center
        children: [
          Text('Chameleon Ultra GUI'), // Display dummy / debug info
          Text('Platform: ${Platform.operatingSystem}'),
          Text('Android: ${appState.onandroid}'),
          Text('Chameleon: ${appState.chameleon}'),
          Text('Serial Ports: ${appState.chameleon.availableDevices()}'),
          Text('Serial Port: ${appState.chameleon.port}'),
          Text('Device: ${appState.chameleon.device}'),
          ElevatedButton(
            // Connect Button
            onPressed: () {
              appState.chameleon
                  .connectDevice(appState.chameleon.availableDevices()[0]);
            },
            child: const Text('Connect'),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () {
              appState.chameleon.sendcommand("test");
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class SavedKeysPage extends StatelessWidget {
  /* Todo list:
  create dynamic list from database.
  2 columns. 1 for description, one for UID?
  Write key to slot upon clicking
  */
  const SavedKeysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Keys'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('Load key?'),
                  content:
                      const Text('Load this key to the currently active slot?'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'Cancel'),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'OK'),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: const Text(
                  'This is where all previously stored keys will be managed'),
            ),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('Load key?'),
                  content:
                      const Text('Load this key to the currently active slot?'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'Cancel'),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'OK'),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              child: const Text(
                  'Clicking on one prompts if you want to put it in the currently active slot'),
            )
          ],
        ),
      ),
    );
  }
}

class SettingsMainPage extends StatelessWidget {
  /* Todo list:
  Think of useful settings that users might want to change
  Make sure we fix (context as Element).reassemble(); under the switch. It's terrible. 
  */
  SettingsMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
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
                print('test');
                //appState.toggleswitch();
                appState.switchOn = !appState.switchOn;
                //(context as Element).reassemble();
                appState.changesMade();
              },
            ),
            ToggleSwitch(
              minWidth: 90.0,
              cornerRadius: 20.0,
              activeFgColor: Colors.white,
              inactiveBgColor: Colors.grey,
              inactiveFgColor: Colors.white,
              initialLabelIndex: appState.expandedIndex,
              totalSwitches: 3,
              labels: ['Expand', 'automatic', 'retract'],
              radiusStyle: true,
              onToggle: (index) {
                if (index == 0) {
                  appState._isExpanded = true;
                  appState.automaticExpansion = false;
                } else if (index == 2) {
                  appState._isExpanded = false;
                  appState.automaticExpansion = false;
                } else {
                  appState.automaticExpansion = true;
                }
                appState.expandedIndex = index;
                appState.changesMade();
              },
            ),
            TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('About'),
                  content: const Text('This app was developed by:....'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'Cancel'),
                      child: const Text('Cancel'),
                    ),
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
                      // Never gonna give you up!
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

// For reference left in
/*
class GeneratorPage extends StatelessWidget {
  const GeneratorPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    /*var pair = appState.current;

    IconData icon;
    if (appState.favorites.contains(pair)) {
      icon = Icons.favorite;
    } else {
      icon = Icons.favorite_border;
    }*/

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BigCard(pair: "AB"),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  //appState.toggleFavorite();
                },
                icon: Icon(Icons.face),
                label: const Text('Like'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  //appState.getNext();
                },
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class BigCard extends StatelessWidget {
  const BigCard({
    super.key,
    required this.pair,
  });

  final String pair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displayMedium!.copyWith(
      color: theme.colorScheme.onPrimary,
    );
    return Card(
      color: theme.colorScheme.primary,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(pair, style: style),
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return ListView(
      children: const [
        Text('Empty'),
      ],
    );
  }
}*/

class CommmodulePC {
  // Class for PC Serial Communication
  SerialPort? port;
  String? device;
  List availableDevices() {
    return SerialPort.availablePorts;
  }

  void connectDevice(String adress) {
    port = SerialPort(adress);
  }

  void sendcommand(String command) {
    print(command);
    print(port);
  }
}

class CommmoduleAndroid {
  // Class for Android Serial Communication
  SerialPort? port;
  String? device;
}

class CommmoduleBLE {}

// https://pub.dev/packages/flutter_libserialport/example <- PC Serial Library
// https://github.com/altera2015/usbserial <- Android Serial Library
