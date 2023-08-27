import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/features/firmware_flasher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sizer_pro/sizer.dart';

// Comms Imports
import 'connector/serial_stub.dart'
  if (dart.library.js) 'connector/serial_web.dart'
  if (Platform.isAndroid) 'connector/serial_mobile.dart'
  if (Platform.isIOS) 'connector/serial_ble.dart'
  if (dart.library.io) 'connector/serial_native.dart';

// Page imports
import 'package:chameleonultragui/gui/page/home.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/mfkey32.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(MyApp(sharedPreferencesProvider));
}

class MyApp extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;

  const MyApp(this._sharedPreferencesProvider, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) => MyAppState(_sharedPreferencesProvider),
        ),
      ],
      child: Sizer(
        builder: (_, __, ___) => MaterialApp(
          title: 'Chameleon Ultra GUI', // App Name
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor:
                    _sharedPreferencesProvider.getThemeColor()), // Color Scheme
            brightness: Brightness.light, // Light Theme
          ),
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.fromSeed(
                seedColor: _sharedPreferencesProvider.getThemeColor(),
                brightness: Brightness.dark), // Color Scheme
            brightness: Brightness.dark, // Dark Theme
          ),
          themeMode: _sharedPreferencesProvider.getTheme(), // Dark Theme
          home: const MyHomePage(),
        )
      )
    );

    //return ChangeNotifierProvider(
    //  create: (context) => MyAppState(),
    //  child:
    //);
  }
}

class MyAppState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  MyAppState(this.sharedPreferencesProvider);
  // State

  bool onAndroid = !kIsWeb && Platform.isAndroid; // Are we on android? (mostly for serial port)
  AbstractSerial connector = SerialConnector(); // Chameleon Object, connected Chameleon
  ChameleonCommunicator? communicator;

  bool devMode = false;
  FlashFirmwareUpdateProgress? flashProgress; // DFU

  // Flashing easter egg
  bool easterEgg = false;

  bool forceMfkey32Page = false;

  Logger log = Logger(); // Logger, App wide logger

  /// Force a complete UI refresh
  /// Not needed when changing state, mainly needed to switch UI after connecting devices
  void changesMade() {
    // log.d('changesMade');
    notifyListeners();
  }

  /// Update the firmware flashing state
  void setFlashProgress(FlashFirmwareUpdateProgress progressUpdate) {
    flashProgress = progressUpdate;
    // log.d('setFlashProgress ${progressUpdate.state} ${progressUpdate.progress}');
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
    if (appState.sharedPreferencesProvider.getSideBarAutoExpansion()) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState.sharedPreferencesProvider.setSideBarExpanded(true);
      } else {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      }
    }

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    Widget page; // Set Page
    if (!appState.connector.connected &&
        selectedIndex != 0 &&
        selectedIndex != 2 &&
        selectedIndex != 5 &&
        selectedIndex != 6) {
      // If not connected, and not on home, settings or dev page, go to home page
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        if (appState.connector.connected) {
          if (appState.connector.isDFU) {
            page = const FlashingPage();
          } else {
            page = const HomePage();
          }
        } else {
          page = const ConnectPage();
        }
        break;
      case 1:
        page = const SlotManagerPage();
        break;
      case 2:
        page = const SavedCardsPage();
        break;
      case 3:
        page = const ReadCardPage();
        break;
      case 4:
        page = const WriteCardPage();
        break;
      case 5:
        page = const SettingsMainPage();
        break;
      case 6:
        page = const DebugPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    if (appState.forceMfkey32Page) {
      appState.forceMfkey32Page = false;
      page = const Mfkey32Page();
    }

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Theme.of(context).colorScheme.surface,
    ));

    final useBottomNavigation = SizerUtil.orientation == Orientation.portrait && SizerUtil.width < 600;
    final useSideNavigation = !useBottomNavigation &&
      (!appState.connector.isDFU ||
      !appState.connector.connected);

    var bottomIndex = selectedIndex;
    if (useBottomNavigation && !appState.connector.connected) {
      // adjust bottomIndex if the device is not connect, cause
      // then we only show 3 buttons as NavigationDestinations
      // cannot be disabled
      if (selectedIndex == 2) {
        bottomIndex = 1;
      }

      if (selectedIndex == 5) {
        bottomIndex = 2;
      }
    }

    return Scaffold(
      body: Row(
        children: [
          if (useSideNavigation)
            SafeArea(
              child: NavigationRail(
                // Sidebar
                extended: appState.sharedPreferencesProvider
                    .getSideBarExpanded(),
                destinations: [
                  // Text color bug on disabled: https://github.com/flutter/flutter/pull/132345
                  // Sidebar Items
                  const NavigationRailDestination(
                    icon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    disabled: appState.connector.connected == false,
                    icon: const Icon(Icons.widgets),
                    label: const Text('Slot Manager'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.auto_awesome_motion_outlined),
                    label: Text('Saved Cards'),
                  ),
                  NavigationRailDestination(
                    disabled: appState.connector.connected == false,
                    icon: const Icon(Icons.wifi),
                    label: const Text('Read Card'),
                  ),
                  NavigationRailDestination(
                    disabled: appState.connector.connected == false,
                    icon: const Icon(Icons.credit_card),
                    label: const Text('Write Card'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    label: Text('Settings'),
                  ),
                  if (appState.devMode)
                    const NavigationRailDestination(
                      icon: Icon(Icons.bug_report),
                      label: Text('🐞 Debug 🐞'),
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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const BottomProgressBar(),
          if (useBottomNavigation)
            NavigationBar(
              destinations: [
                NavigationDestination(
                  icon: Icon(bottomIndex == 0 && appState.connector.connected ? Icons.close : Icons.home),
                  label: 'Home',
                ),
                if (appState.connector.connected)
                  const NavigationDestination(
                    // enabled: appState.connector.connected == false,
                    icon: Icon(Icons.widgets),
                    label: 'Slots',
                    tooltip: 'Slot Manager',
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.auto_awesome_motion_outlined),
                  label: 'Saved',
                  tooltip: 'Saved Cards',
                ),
                if (appState.connector.connected)
                  const NavigationDestination(
                    // disabled: appState.connector.connected == false,
                    icon: Icon(Icons.wifi),
                    label: 'Read',
                    tooltip: 'Read Card',
                  ),
                if (appState.connector.connected)
                  const NavigationDestination(
                    // disabled: ,
                    icon: Icon(Icons.credit_card),
                    label: 'Write',
                    tooltip: 'Write Card',
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
                if (appState.devMode)
                  const NavigationDestination(
                    icon: Icon(Icons.bug_report),
                    label: '🐞 Debug 🐞',
                  ),
              ],
              selectedIndex: bottomIndex,
              onDestinationSelected: (value) {
                if (!appState.connector.connected) {
                  if (value == 1) {
                    value = 2;
                  } else if (value == 2) {
                    value = 5;
                  }
                } else if (value == 0 && bottomIndex == 0) {
                  // If user taps on Home icon while already on Home page
                  // then close the active device port
                  appState.connector.performDisconnect().then((_) => appState.changesMade());
                }

                setState(() {
                  selectedIndex = value;
                });
              },
            )
          ]
      )
    );
  }
}

class BottomProgressBar extends StatelessWidget {
  const BottomProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    return (appState.connector.connected == true &&
            appState.connector.isDFU &&
            (appState.flashProgress!.progress != null && appState.flashProgress!.progress !> 0))
        ? LinearProgressIndicator(
            value: appState.flashProgress!.progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          )
        : const SizedBox();
  }
}
