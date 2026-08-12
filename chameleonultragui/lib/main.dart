import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/helpers/font.dart';
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
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/gui/page/pending_connection.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

enum NavigationPage {
  home,
  slotManager,
  savedCards,
  readCard,
  writeCard,
  tools,
  settings,
  debug,
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(ChameleonGUI(sharedPreferencesProvider));
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {super.key});

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

  bool devMode = false;
  double? progress; // DFU

  // Flashing easter egg
  bool easterEgg = false;
  dynamic _suppressedAutoReconnectPort;

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

  void changesMade() {
    notifyListeners();
  }

  void onConnectorStateChanged() {
    if (connector == null || !connector!.connected) {
      communicator = null;
      progress = null;
    }
    notifyListeners();
  }

  bool isAutoReconnectSuppressed(dynamic devicePort) {
    return _suppressedAutoReconnectPort == devicePort;
  }

  void clearAutoReconnectSuppression([dynamic devicePort]) {
    if (devicePort == null || _suppressedAutoReconnectPort == devicePort) {
      _suppressedAutoReconnectPort = null;
    }
  }

  void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts) {
    if (_suppressedAutoReconnectPort == null) {
      return;
    }

    for (final port in visiblePorts) {
      if (port == _suppressedAutoReconnectPort) {
        return;
      }
    }

    _suppressedAutoReconnectPort = null;
  }

  Future<void> disconnect({bool manual = false}) async {
    final suppressedPort = manual ? connector?.activeDevicePort : null;
    await connector?.performDisconnect();
    if (manual && suppressedPort != null) {
      _suppressedAutoReconnectPort = suppressedPort;
    }
    communicator = null;
    progress = null;
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
  static const double _compactWidthBreakpoint = 700;

  static const List<NavigationPage> _primaryTabPages = [
    NavigationPage.home,
    NavigationPage.savedCards,
    NavigationPage.readCard,
    NavigationPage.tools,
  ];

  static const List<NavigationPage> _deviceOnlyPages = [
    NavigationPage.slotManager,
    NavigationPage.readCard,
    NavigationPage.writeCard,
  ];

  NavigationPage selectedPage = NavigationPage.home;

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
    await appState.disconnect();

    super.reassemble();
  }

  AbstractSerial getConnector(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isEmulatedChameleon()) {
      return EmulatorSerial(log: appState.log!);
    }

    if (Platform.isMacOS) {
      return MacOSSerial(log: appState.log!);
    }

    if (Platform.isAndroid) {
      return AndroidSerial(log: appState.log!);
    }

    if (Platform.isIOS) {
      return BLESerial(log: appState.log!);
    }

    return NativeSerial(log: appState.log!);
  }

  Logger getLogger(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isDebugLogging() &&
        appState._sharedPreferencesProvider!.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(appState._sharedPreferencesProvider!),
        printer: PrettyPrinter(
          noBoxingByDefault: true,
        ),
        filter: ChameleonLogFilter(),
      );
    } else {
      return Logger();
    }
  }

  int get _moreTabIndex => _primaryTabPages.length;

  int _bottomNavSelectedIndex(NavigationPage page) {
    var tab = _primaryTabPages.indexOf(page);
    return tab == -1 ? _moreTabIndex : tab;
  }

  void _showDeviceRequired(BuildContext context) {
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    var localizations = AppLocalizations.of(context)!;

    scaffoldMessenger.hideCurrentSnackBar();
    var snackBar = SnackBar(
      content: Text(localizations.device_required),
      action: SnackBarAction(
        label: localizations.close,
        onPressed: () {},
      ),
    );

    scaffoldMessenger.showSnackBar(snackBar);
  }

  void _onBottomNavSelected(
      BuildContext context, ChameleonGUIState appState, int value) {
    if (value == _moreTabIndex) {
      _showMoreMenu(context);
      return;
    }

    _goToPage(context, appState, _primaryTabPages[value]);
  }

  void _goToPage(
      BuildContext context, ChameleonGUIState appState, NavigationPage page) {
    if (_deviceOnlyPages.contains(page) && !appState.connector!.connected) {
      _showDeviceRequired(context);
      return;
    }

    setState(() {
      selectedPage = page;
    });
  }

  void _showMoreMenu(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Consumer<ChameleonGUIState>(
        builder: (_, appState, __) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _moreMenuItem(context, appState, Icons.widgets,
                  localizations.slot_manager, NavigationPage.slotManager),
              _moreMenuItem(context, appState, Icons.system_update_alt,
                  localizations.write_card, NavigationPage.writeCard),
              _moreMenuItem(context, appState, Icons.settings,
                  localizations.settings, NavigationPage.settings),
              if (appState.devMode)
                _moreMenuItem(context, appState, Icons.bug_report,
                    '🐞 ${localizations.debug} 🐞', NavigationPage.debug),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreMenuItem(BuildContext context, ChameleonGUIState appState,
      IconData icon, String label, NavigationPage page) {
    var needsDevice =
        _deviceOnlyPages.contains(page) && !appState.connector!.connected;
    return ListTile(
      leading: Icon(icon,
          color: needsDevice ? Theme.of(context).disabledColor : null),
      title: Text(label),
      selected: selectedPage == page,
      onTap: () {
        Navigator.of(context).pop();
        _goToPage(context, appState, page);
      },
    );
  }

  NavigationBar _buildBottomNavigationBar(
      BuildContext context, ChameleonGUIState appState) {
    var localizations = AppLocalizations.of(context)!;
    var connected = appState.connector!.connected;
    return NavigationBar(
      selectedIndex: _bottomNavSelectedIndex(selectedPage),
      onDestinationSelected: (value) =>
          _onBottomNavSelected(context, appState, value),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home),
          label: localizations.home,
        ),
        NavigationDestination(
          icon: const Icon(Icons.auto_awesome_motion),
          label: localizations.saved_cards,
        ),
        NavigationDestination(
          icon: Icon(Icons.sensors,
              color: connected ? null : Theme.of(context).disabledColor),
          label: localizations.read_card,
        ),
        NavigationDestination(
          icon: const Icon(Icons.handyman),
          label: localizations.tools,
        ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz),
          label: localizations.more,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    appState._sharedPreferencesProvider = widget.sharedPreferencesProvider;
    appState.log ??= getLogger(appState);
    appState.connector ??= getConnector(appState);
    appState.connector!.connectionStateCallback =
        appState.onConnectorStateChanged;

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
    if (!appState.connector!.connected &&
        _deviceOnlyPages.contains(selectedPage)) {
      selectedPage = NavigationPage.home;
    }

    switch (selectedPage) {
      // Sidebar Navigation
      case NavigationPage.home:
        if (appState.connector!.pendingConnection) {
          page = const PendingConnectionPage();
        } else {
          if (appState.connector!.connected) {
            if (appState.connector!.isDFU) {
              page = const FlashingPage();
            } else {
              page = const HomePage();
            }
          } else {
            page = const ConnectPage();
          }
        }
        break;
      case NavigationPage.slotManager:
        page = const SlotManagerPage();
        break;
      case NavigationPage.savedCards:
        page = const SavedCardsPage();
        break;
      case NavigationPage.readCard:
        page = const ReadCardPage();
        break;
      case NavigationPage.writeCard:
        page = const WriteCardPage();
        break;
      case NavigationPage.tools:
        page = const ToolsPage();
        break;
      case NavigationPage.settings:
        page = const SettingsMainPage();
        break;
      case NavigationPage.debug:
        page = const DebugPage();
        break;
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
      ).useCustomSystemFont(Brightness.light),
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
                statusBarIconBrightness: Brightness.light)),
      ).useCustomSystemFont(Brightness.dark),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      home: LayoutBuilder(// Build Page
          builder: (context, constraints) {
        final showNavigation =
            !(appState.connector!.isDFU && appState.connector!.connected);
        final useRail = constraints.maxWidth >= _compactWidthBreakpoint;
        return SafeArea(
          left: false,
          right: false,
          top: false,
          bottom: useRail || !showNavigation, // NavigationBar insets when shown
          child: Scaffold(
              body: Row(
                children: [
                  (useRail && showNavigation)
                      ? SafeArea(
                          child: NavigationRail(
                            key: appState.navigationRailKey,
                            // Sidebar
                            extended: appState.sharedPreferencesProvider
                                .getSideBarExpanded(),
                            destinations: [
                              // Sidebar Items
                              NavigationRailDestination(
                                icon: const Icon(Icons.home),
                                label: Text(
                                    AppLocalizations.of(context)!.home), // Home
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: const Icon(Icons.widgets),
                                label: Text(
                                    AppLocalizations.of(context)!.slot_manager),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.auto_awesome_motion),
                                label: Text(
                                    AppLocalizations.of(context)!.saved_cards),
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: const Icon(Icons.sensors),
                                label: Text(
                                    AppLocalizations.of(context)!.read_card),
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: const Icon(Icons.system_update_alt),
                                label: Text(
                                    AppLocalizations.of(context)!.write_card),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.handyman),
                                label:
                                    Text(AppLocalizations.of(context)!.tools),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.settings),
                                label: Text(
                                    AppLocalizations.of(context)!.settings),
                              ),
                              if (appState.devMode)
                                NavigationRailDestination(
                                  icon: const Icon(Icons.bug_report),
                                  label: Text(
                                      '🐞 ${AppLocalizations.of(context)!.debug} 🐞'),
                                ),
                            ],
                            selectedIndex: selectedPage.index,
                            onDestinationSelected: (value) {
                              setState(() {
                                selectedPage = NavigationPage.values[value];
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
              bottomNavigationBar: useRail
                  ? const BottomProgressBar()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BottomProgressBar(),
                        if (showNavigation)
                          _buildBottomNavigationBar(context, appState),
                      ],
                    )),
        );
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
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          )
        : const SizedBox();
  }
}
