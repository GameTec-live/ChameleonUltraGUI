import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connector/serial_native.dart';

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
import 'package:chameleonultragui/gui/page/pending_connection.dart';
import 'package:chameleonultragui/gui/page/info.dart';
import 'package:chameleonultragui/gui/page/recovery.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(ChameleonGUI(sharedPreferencesProvider));
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) => ChameleonGUIState(_sharedPreferencesProvider),
        ),
      ],
      child: MainPage(sharedPreferencesProvider: _sharedPreferencesProvider),
    );
  }
}

class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider);

  SharedPreferencesProvider? _sharedPreferencesProvider;
  Logger? log; // Logger

  // Android uses AndroidSerial, iOS can only use BLESerial
  // The rest (desktops?) can use NativeSerial
  AbstractSerial? connector;
  ChameleonCommunicator? communicator;

  bool devMode = true;
  double? progress; // DFU

  // Flashing easter egg
  bool easterEgg = false;

  bool reader_enabled = false;

  bool forceMfkey32Page = false;

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

  void changesMade() {
    notifyListeners();
  }

  void setProgressBar(dynamic value) {
    progress = value;
    notifyListeners();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => updateNavigationRailWidth(context));
  }

  @override
  void reassemble() async {
    // Disconnect on reload
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    await appState.connector?.performDisconnect();
    appState.changesMade();

    super.reassemble();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    appState._sharedPreferencesProvider = widget.sharedPreferencesProvider;
    appState.log ??= Logger(
        output: appState._sharedPreferencesProvider!.isDebugLogging()
            ? SharedPreferencesLogger(appState._sharedPreferencesProvider!)
            : ConsoleOutput(),
        printer: PrettyPrinter(
          noBoxingByDefault:
              appState._sharedPreferencesProvider!.isDebugLogging(),
        ),
        filter: ChameleonLogFilter());
    appState.connector ??= Platform.isAndroid
        ? AndroidSerial(log: appState.log!)
        : (Platform.isIOS
            ? BLESerial(log: appState.log!)
            : NativeSerial(log: appState.log!));
    if (appState.sharedPreferencesProvider.getSideBarAutoExpansion()) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      } else {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      }
    }

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    Widget page; 
    if (!appState.connector!.connected &&
        selectedIndex != 0 &&
        selectedIndex != 2 &&
        selectedIndex != 5 &&
        selectedIndex != 6 &&
        selectedIndex != 7 &&
        selectedIndex != 8 &&
        selectedIndex != 9 &&
        selectedIndex != 10) {
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      case 0:
        if (appState.connector!.pendingConnection) {
          page = const PendingConnectionPage();
        } else {
          if (appState.connector!.connected) {
            if (appState.connector!.isDFU) {
              page = const FlashingPage();
            } else {
              page = const SavedCardsPage();
            }
          } else {
            page = const ConnectPage();
          }
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
      case 7:
        page = const InfoPage();
        break;
      case 8:
        bool new_reader_state = !appState.reader_enabled;
        appState.communicator!.setReaderDeviceMode(new_reader_state);
        //appState.changesMade();
        page = const ReadCardPage();
        break;
      case 9:
        page = const RecoveryPage();
        break;
      case 10:
        appState.connector!.performDisconnect();
        appState.changesMade();
        page = const ConnectPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    if (appState.forceMfkey32Page) {
      appState.forceMfkey32Page = false;
      page = const Mfkey32Page();
    }

    try {
      WakelockPlus.toggle(enable: page is FlashingPage);
    } catch (_) {}

    return MaterialApp(
      title: 'Chameleon Ultra GUI', // App Name
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: widget.sharedPreferencesProvider.getThemeColor()),
        brightness: Brightness.light,
        appBarTheme: AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: ColorScheme.fromSeed(
                        seedColor:
                            widget.sharedPreferencesProvider.getThemeColor(),
                        brightness: Brightness.light)
                    .surface,
                statusBarBrightness: Brightness.light,
                statusBarIconBrightness: Brightness.dark)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: widget.sharedPreferencesProvider.getThemeColor(),
            brightness: Brightness.dark),
        brightness: Brightness.dark,
        appBarTheme: AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: ColorScheme.fromSeed(
                        seedColor:
                            widget.sharedPreferencesProvider.getThemeColor(),
                        brightness: Brightness.dark)
                    .surface,
                statusBarBrightness: Brightness.dark,
                statusBarIconBrightness: Brightness.dark)),
      ),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      home: LayoutBuilder(// Build Page
          builder: (context, constraints) {
        return Scaffold(
            body: Row(
              children: [
                (!appState.connector!.isDFU || !appState.connector!.connected)
                    ? SafeArea(
                        child: NavigationRail(
                          key: appState.navigationRailKey,
                          // Sidebar
                          extended: appState.sharedPreferencesProvider
                              .getSideBarExpanded(),
                          destinations: [
                            // Sidebar Items
                            NavigationRailDestination(
                              icon: const Icon(Icons.memory_sharp),
                              label: Text(
                                  AppLocalizations.of(context)!.home), // Home
                            ),
                            NavigationRailDestination(
                              disabled: (!appState.connector!.connected || !appState.sharedPreferencesProvider.isShowAll()),
                              icon: const Icon(Icons.widgets),
                              label: Text(
                                  AppLocalizations.of(context)!.slot_manager),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(
                                  Icons.auto_awesome_motion_outlined),
                              label: Text(
                                  AppLocalizations.of(context)!.saved_cards),
                            ),
                            NavigationRailDestination(
                              disabled: (!appState.connector!.connected || appState.sharedPreferencesProvider.isShowAll()),
                              icon: const Icon(Icons.wifi),
                              label:
                                  Text(AppLocalizations.of(context)!.read_card),
                            ),
                            NavigationRailDestination(
                              disabled: (!appState.connector!.connected || appState.sharedPreferencesProvider.isShowAll()),
                              icon: const Icon(Icons.credit_card),
                              label: Text(
                                  AppLocalizations.of(context)!.write_card),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.settings),
                              label:
                                  Text(AppLocalizations.of(context)!.settings),
                            ),
                            if (appState.devMode)
                              NavigationRailDestination(
                                icon: const Icon(Icons.adb),
                                label: Text(
                                    '${AppLocalizations.of(context)!.debug}'),
                              ),
                            NavigationRailDestination(
                              //disabled: (!appState.connector!.connected || appState.sharedPreferencesProvider.isShowAll()),
                              icon: const Icon(Icons.info),
                              label:
                                  Text("Info"),
                            ),
                            NavigationRailDestination(
                              disabled: (!appState.connector!.connected || appState.sharedPreferencesProvider.isShowAll()),
                              icon: const Icon(Icons.radio),
                              label:
                                  Text("HF Reader"),
                            ),
                            NavigationRailDestination(
                              disabled: (!appState.connector!.connected || appState.sharedPreferencesProvider.isShowAll()),
                              icon: const Icon(Icons.key),
                              label:
                                  Text("Recoery"),
                            ),
                            NavigationRailDestination(
                              //disabled: (!appState.connector!.connected || !appState.sharedPreferencesProvider.isShowAll()),
                              icon: const Icon(Icons.power_settings_new),
                              label:
                                  Text("Restart"),
                            ),
                          ],
                          selectedIndex: selectedIndex,
                          onDestinationSelected: (value) {
                            setState(() {
                              selectedIndex = value;
                            });
                          },
                        ),
                      )
                    : const SizedBox(),
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: page,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: const BottomProgressBar());
      }),
    );
  }
}

class BottomProgressBar extends StatelessWidget {
  const BottomProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    return (appState.connector!.connected && appState.connector!.isDFU)
        ? LinearProgressIndicator(
            value: appState.progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.pink),
          )
        : const SizedBox();
  }
}
