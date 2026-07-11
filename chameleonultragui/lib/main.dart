import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/helpers/font.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connector/serial_native.dart';

// Page imports
import 'package:chameleonultragui/gui/page/home.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/pending_connection.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

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

class ChameleonGUI extends StatefulWidget {
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {super.key});

  @override
  State<ChameleonGUI> createState() => _ChameleonGUIState();
}

class _ChameleonGUIState extends State<ChameleonGUI> {
  late final ChameleonGUIState appState;
  late final GoRouter router;

  @override
  void initState() {
    super.initState();
    appState = ChameleonGUIState(widget._sharedPreferencesProvider);
    router = AppRouter.create(appState);
  }

  @override
  void dispose() {
    router.dispose();
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget._sharedPreferencesProvider),
        ChangeNotifierProvider.value(value: appState),
      ],
      child: Consumer<SharedPreferencesProvider>(
        builder: (context, preferences, child) => MaterialApp.router(
          title: 'Chameleon Ultra GUI',
          routerConfig: router,
          locale: preferences.getLocale(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _theme(preferences, Brightness.light),
          darkTheme: _theme(preferences, Brightness.dark),
          themeMode: preferences.getTheme(),
        ),
      ),
    );
  }

  ThemeData _theme(
    SharedPreferencesProvider preferences,
    Brightness brightness,
  ) {
    final colors = ColorScheme.fromSeed(
      seedColor: preferences.getThemeColor(),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      brightness: brightness,
      appBarTheme: AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: colors.surface,
          statusBarBrightness: brightness,
          statusBarIconBrightness: brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
        ),
      ),
    ).useCustomSystemFont(brightness);
  }
}

class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider) {
    devMode = sharedPreferencesProvider.isDebugMode();
    log = _createLogger();
    connector = _createConnector();
    connector!.connectionStateCallback = onConnectorStateChanged;
  }

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
    devMode = sharedPreferencesProvider.isDebugMode();
    notifyListeners();
  }

  AbstractSerial _createConnector() {
    if (sharedPreferencesProvider.isEmulatedChameleon()) {
      return EmulatorSerial(log: log!);
    }
    if (Platform.isMacOS) return MacOSSerial(log: log!);
    if (Platform.isAndroid) return AndroidSerial(log: log!);
    if (Platform.isIOS) return BLESerial(log: log!);
    return NativeSerial(log: log!);
  }

  Logger _createLogger() {
    if (sharedPreferencesProvider.isDebugLogging() &&
        sharedPreferencesProvider.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(sharedPreferencesProvider),
        printer: PrettyPrinter(noBoxingByDefault: true),
        filter: ChameleonLogFilter(),
      );
    }
    return Logger();
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

class HomeRouterPage extends StatelessWidget {
  const HomeRouterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<ChameleonGUIState>().connector!;
    if (connector.pendingConnection) return const PendingConnectionPage();
    if (!connector.connected) return const ConnectPage();
    if (connector.isDFU) return const FlashingPage();
    return const HomePage();
  }
}

class AppNavigationShell extends StatefulWidget {
  const AppNavigationShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  State<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends State<AppNavigationShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => updateNavigationRailWidth(context));
  }

  @override
  void reassemble() {
    context.read<ChameleonGUIState>().disconnect();
    super.reassemble();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final preferences = appState.sharedPreferencesProvider;
    final connector = appState.connector!;
    final width = MediaQuery.sizeOf(context).width;
    final expanded = preferences.getSideBarAutoExpansion()
        ? width >= 600
        : preferences.getSideBarExpanded();

    try {
      WakelockPlus.toggle(enable: connector.connected && connector.isDFU);
    } catch (_) {}

    final localizations = AppLocalizations.of(context)!;
    final destinations = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: const Icon(Icons.home),
        label: Text(localizations.home),
      ),
      NavigationRailDestination(
        disabled: !connector.connected,
        icon: const Icon(Icons.widgets),
        label: Text(localizations.slot_manager),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.auto_awesome_motion),
        label: Text(localizations.saved_cards),
      ),
      NavigationRailDestination(
        disabled: !connector.connected,
        icon: const Icon(Icons.sensors),
        label: Text(localizations.read_card),
      ),
      NavigationRailDestination(
        disabled: !connector.connected,
        icon: const Icon(Icons.system_update_alt),
        label: Text(localizations.write_card),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.handyman),
        label: Text(localizations.tools),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings),
        label: Text(localizations.settings),
      ),
      if (appState.devMode)
        NavigationRailDestination(
          icon: const Icon(Icons.bug_report),
          label: Text('🐞 ${localizations.debug} 🐞'),
        ),
    ];

    return SafeArea(
      left: false,
      right: false,
      top: false,
      child: Scaffold(
        body: Row(
          children: [
            if (!connector.connected || !connector.isDFU)
              SafeArea(
                child: NavigationRail(
                  key: appState.navigationRailKey,
                  extended: expanded,
                  destinations: destinations,
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: (index) =>
                      widget.navigationShell.goBranch(
                    index,
                    initialLocation:
                        index == widget.navigationShell.currentIndex,
                  ),
                ),
              ),
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: widget.navigationShell,
              ),
            ),
          ],
        ),
        bottomNavigationBar: const BottomProgressBar(),
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
