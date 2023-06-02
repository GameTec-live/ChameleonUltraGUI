import 'dart:io';
import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// GUI Imports
import 'gui/homepage.dart';
import 'gui/savedkeyspage.dart';
import 'gui/settingspage.dart';
import 'gui/connectpage.dart';

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
  bool onAndroid =
      Platform.isAndroid; // Are we on android? (mostly for serial port)
  AbstractSerial chameleon = AbstractSerial(); // Chameleon Object, connected Chameleon
  bool switchOn = true;
  /*void toggleswitch() {
    setState(() {
      switchOn = !switchOn;
    })
  }
  // This doesn't work because we aren't working stateful
  */
  var isExpanded =
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
    /*if (appState.onAndroid) { // Redefining the Chameleon clears everything, it is also already defined as AbstractSerial on line 45
      // Set Chameleon Object
      appState.chameleon = MobileSerial();
    } else {
      appState.chameleon = NativeSerial();
    }*/
    if (appState.automaticExpansion) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState.isExpanded = true;
      } else {
        appState.isExpanded = false;
      }
    }

    Widget page; // Set Page
    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        if (appState.chameleon.connected == true) {
          page = const HomePage();
        } else {
          page = const ConnectPage();
        }
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
        page = const SettingsMainPage();
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
                extended: appState.isExpanded,
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

// Moved reference: https://pastebin.com/raw/cjt3EyiF