import 'dart:async';
import 'dart:io';

import 'package:chameleonultragui/ble_stress.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/connector/serial_windows.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/gui/page/plugins.dart';
import 'package:chameleonultragui/helpers/font.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/ble_pairing.dart';
import 'package:chameleonultragui/helpers/window_state.dart';
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

import 'package:chameleonultragui/plugins/store.dart';
import 'package:chameleonultragui/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.environment['CHAMELEON_BLE_STRESS'] == '1') {
    runApp(const _BleStressApp());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      hideApplicationWindow();
      await runBleStress();
    });
    return;
  }
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  await WindowStateKeeper.instance.restore();
  final sync = SyncService(sharedPreferencesProvider.preferences);
  sharedPreferencesProvider.onLocalChange = sync.localChanged;
  sync.start();
  runApp(ChameleonGUI(sharedPreferencesProvider, sync));
  WindowStateKeeper.instance.start();
}

class _BleStressApp extends StatelessWidget {
  const _BleStressApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(backgroundColor: Colors.black, body: SizedBox.expand()),
    );
  }
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  final SyncService _sync;
  const ChameleonGUI(this._sharedPreferencesProvider, this._sync, {super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider.value(value: _sync),
        ChangeNotifierProvider(
          create: (context) => ChameleonGUIState(_sharedPreferencesProvider)
            // Remote data changed settings, cards, ...: rebuild everything.
            ..watchSync(_sync),
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

  void watchSync(SyncService sync) {
    sync.onRemoteChange = (collections) {
      if (collections.contains('plugins')) PluginStore.remoteChanges.value++;
      changesMade();
    };
  }

  void onConnectorStateChanged() {
    final current = connector;
    if (current != null && current.connected && !current.isDFU) {
      communicator ??= ChameleonCommunicator(log!, port: current);
    }
    if (current == null || !current.connected) {
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
  var selectedIndex = 0;
  Timer? _keepAliveTimer;
  bool _keepAliveInFlight = false;
  dynamic _pairingCheckedPort;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => updateNavigationRailWidth(context),
    );
    // The firmware keeps running while BLE is connected, but powers off a few
    // seconds after the link drops. A lightweight periodic command keeps both
    // the BLE link and the device awake while the app is open.
    _keepAliveTimer = Timer.periodic(
      const Duration(milliseconds: 1000),
      (_) => sendKeepAlive(),
    );
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    super.dispose();
  }

  Future<void> sendKeepAlive() async {
    if (_keepAliveInFlight || !mounted) {
      return;
    }

    final appState = Provider.of<ChameleonGUIState>(context, listen: false);
    final communicator = appState.communicator;
    final connector = appState.connector;
    if (communicator == null ||
        connector == null ||
        !connector.connected ||
        connector.isDFU ||
        communicator.commandQueue.isNotEmpty) {
      return;
    }

    _keepAliveInFlight = true;
    try {
      await communicator.keepAlive();
    } catch (error) {
      appState.log?.w('Keep-alive ping failed: $error');
    } finally {
      _keepAliveInFlight = false;
    }
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

    if (Platform.isWindows) {
      return WindowsSerial(log: appState.log!);
    }

    return NativeSerial(log: appState.log!);
  }

  Logger getLogger(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isDebugLogging() &&
        appState._sharedPreferencesProvider!.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(appState._sharedPreferencesProvider!),
        printer: PrettyPrinter(noBoxingByDefault: true),
        filter: ChameleonLogFilter(),
      );
    } else {
      return Logger();
    }
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

    // Ask for the BLE PIN once per connection only when the device itself
    // reports that pairing is required and no bond exists yet.
    if (appState.connector!.connected &&
        !appState.connector!.isDFU &&
        appState.connector!.connectionType == ConnectionType.ble) {
      final port = appState.connector!.activeDevicePort;
      if (port != null && port != _pairingCheckedPort) {
        _pairingCheckedPort = port;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ensureBlePairing(context, appState);
          }
        });
      }
    } else if (!appState.connector!.connected) {
      _pairingCheckedPort = null;
      forgetBlePairingPort();
    }

    Widget page; // Set Page
    if (!appState.connector!.connected &&
        selectedIndex != 0 &&
        selectedIndex != 2 &&
        selectedIndex != 5 &&
        selectedIndex != 6 &&
        selectedIndex != 7 &&
        selectedIndex != 8) {
      // Offline pages remain available without a device.
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
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
        page = const ToolsPage();
        break;
      case 6:
        page = const PluginsPage();
        break;
      case 7:
        page = const SettingsMainPage();
        break;
      case 8:
        page = const DebugPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    try {
      WakelockPlus.toggle(
        enable: page is FlashingPage || appState.connector!.connected,
      );
    } catch (_) {}

    return MaterialApp(
      title: 'Chameleon Ultra GUI', // App Name
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: widget.sharedPreferencesProvider.getThemeColor(),
        ),
        brightness: Brightness.light,
        appBarTheme: AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: ColorScheme.fromSeed(
              seedColor: widget.sharedPreferencesProvider.getThemeColor(),
              brightness: Brightness.light,
            ).surface,
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
      ).useCustomSystemFont(Brightness.light),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: widget.sharedPreferencesProvider.getThemeColor(),
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
        appBarTheme: AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: ColorScheme.fromSeed(
              seedColor: widget.sharedPreferencesProvider.getThemeColor(),
              brightness: Brightness.dark,
            ).surface,
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
      ).useCustomSystemFont(Brightness.dark),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      home: LayoutBuilder(
        // Build Page
        builder: (context, constraints) {
          return SafeArea(
            left: false,
            right: false,
            top: false,
            bottom: true,
            child: Scaffold(
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
                                icon: const Icon(Icons.home),
                                label: Text(
                                  AppLocalizations.of(context)!.home,
                                ), // Home
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: const Icon(Icons.widgets),
                                label: Text(
                                  AppLocalizations.of(context)!.slot_manager,
                                ),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.auto_awesome_motion),
                                label: Text(
                                  AppLocalizations.of(context)!.saved_cards,
                                ),
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: const Icon(Icons.sensors),
                                label: Text(
                                  AppLocalizations.of(context)!.read_card,
                                ),
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: const Icon(Icons.system_update_alt),
                                label: Text(
                                  AppLocalizations.of(context)!.write_card,
                                ),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.handyman),
                                label: Text(
                                  AppLocalizations.of(context)!.tools,
                                ),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.extension),
                                label: Text(
                                  AppLocalizations.of(context)!.plugins,
                                ),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.settings),
                                label: Text(
                                  AppLocalizations.of(context)!.settings,
                                ),
                              ),
                              if (appState.devMode)
                                NavigationRailDestination(
                                  icon: const Icon(Icons.bug_report),
                                  label: Text(
                                    '🐞 ${AppLocalizations.of(context)!.debug} 🐞',
                                  ),
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
              bottomNavigationBar: const BottomProgressBar(),
            ),
          );
        },
      ),
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
