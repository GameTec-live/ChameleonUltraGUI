// Widget tests for deep links: the chameleonultra:// and cugui:// URL schemes
// handled by MainPage through app_links. The app_links platform channels are
// mocked, so the tests need neither a device nor the native plugin.
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/plugins.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/sync.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const events = EventChannel('com.llfbandit.app_links/events');
const methods = MethodChannel('com.llfbandit.app_links/messages');

void main() {
  late SharedPreferencesProvider prefs;
  late SyncService sync;
  late List<String> launchLinks; // emitted as soon as Dart listens (cold start)
  MockStreamHandlerEventSink? sink;
  int initialLinkCalls = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'emulate_device': true});
    prefs = SharedPreferencesProvider();
    await prefs.load();
    sync = SyncService(prefs.preferences);
    launchLinks = [];
    sink = null;
    initialLinkCalls = 0;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(methods, (call) async {
      initialLinkCalls++;
      return null;
    });
    m.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (args, s) {
          sink = s;
          for (final l in launchLinks) {
            s.success(l);
          }
        },
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(ChameleonGUI(prefs, sync));
    // Let the app's existing 500ms updateNavigationRailWidth timer finish while
    // the rail is still visible (it null-checks the rail context).
    await tester.pump(const Duration(milliseconds: 600));
  }

  ChameleonGUIState appState(WidgetTester t) => Provider.of<ChameleonGUIState>(
    t.element(find.byType(MainPage)),
    listen: false,
  );

  Future<void> emit(WidgetTester t, String link) async {
    sink!.success(link);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('cold start: buffered launch link is handled via stream only', (
    t,
  ) async {
    launchLinks = ['chameleonultra://settings'];
    await pumpApp(t);
    expect(find.byType(SettingsMainPage), findsOneWidget);
    expect(initialLinkCalls, 0, reason: 'getInitialLink must not be called');
    expect(find.byType(MainPage), findsOneWidget);
    // Drain the app's 500ms rail-width timer before the test ends.
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('warm links switch pages; unknown/foreign ignored', (t) async {
    await pumpApp(t);
    expect(find.byType(ConnectPage), findsOneWidget);
    await emit(t, 'chameleonultra://saved-cards');
    expect(find.byType(SavedCardsPage), findsOneWidget);
    await emit(t, 'chameleonultra://bogus');
    expect(find.byType(SavedCardsPage), findsOneWidget);
    await emit(t, 'https://settings');
    expect(find.byType(SavedCardsPage), findsOneWidget);
    await emit(t, 'chameleonultra://read'); // offline -> falls back
    expect(find.byType(ConnectPage), findsOneWidget);
    // Drain the app's 500ms rail-width timer before the test ends.
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('links ignored while connected in DFU mode', (t) async {
    await pumpApp(t);
    final c = appState(t).connector!;
    c.connected = true;
    c.isDFU = true;
    appState(t).changesMade();
    await t.pump();
    expect(find.byType(FlashingPage), findsOneWidget);
    await emit(t, 'chameleonultra://settings');
    expect(find.byType(FlashingPage), findsOneWidget);
    expect(find.byType(SettingsMainPage), findsNothing);
    // Drain the app's 500ms rail-width timer before the test ends.
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('links still work while a connection is pending', (t) async {
    await pumpApp(t);
    final c = appState(t).connector!;
    c.pendingConnection = true;
    appState(t).changesMade();
    await t.pump();
    await emit(t, 'chameleonultra://settings');
    expect(find.byType(SettingsMainPage), findsOneWidget);
    // Drain the app's 500ms rail-width timer before the test ends.
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('stream error is logged, not swallowed; stream keeps working', (
    t,
  ) async {
    final printed = <String>[];
    final orig = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
    await pumpApp(t);
    appState(t).log = null; // force the debugPrint fallback path
    sink!.error(code: 'X', message: 'boom');
    await t.pump();
    debugPrint = orig;
    expect(printed.any((m) => m.contains('Deep link error')), isTrue);
    await emit(t, 'chameleonultra://settings');
    expect(find.byType(SettingsMainPage), findsOneWidget);
    // Drain the app's 500ms rail-width timer before the test ends.
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('dispose cancels the subscription', (t) async {
    await pumpApp(t);
    expect(sink, isNotNull);
    await t.pumpWidget(const SizedBox());
    // Emitting after dispose must not throw (no setState after dispose).
    sink!.success('chameleonultra://settings');
    await t.pump();
    expect(t.takeException(), isNull);
    // Drain the app's 500ms rail-width timer before the test ends.
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('link during DFU reconnect window cannot strand the user', (
    t,
  ) async {
    await pumpApp(t);
    // flashFirmware() has disconnected and is polling for the DFU device:
    // connected == false, isDFU == false, pendingConnection == false.
    await emit(t, 'chameleonultra://settings');
    expect(find.byType(SettingsMainPage), findsOneWidget);
    final c = appState(t).connector!;
    c.connected = true; // DFU device found and connected
    c.isDFU = true;
    appState(t).changesMade();
    await t.pump();
    expect(find.byType(FlashingPage), findsOneWidget);
    expect(find.byType(SettingsMainPage), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('link is ignored and logged while a sub-page is open', (t) async {
    final printed = <String>[];
    final orig = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
    await pumpApp(t);
    await emit(t, 'chameleonultra://settings');
    appState(t).log = null; // force the debugPrint fallback path
    final btn = find.byIcon(Icons.sync);
    await t.ensureVisible(btn.first);
    await t.pump();
    await t.tap(btn.first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(SyncPage), findsOneWidget);
    await emit(t, 'chameleonultra://cards');
    await t.pump(const Duration(seconds: 1));
    debugPrint = orig;
    expect(find.byType(SyncPage), findsOneWidget);
    expect(find.byType(SettingsMainPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(SavedCardsPage, skipOffstage: false), findsNothing);
    expect(printed.any((m) => m.contains('Deep link ignored')), isTrue);
    // After closing the sub-page, links work again.
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await emit(t, 'chameleonultra://cards');
    expect(find.byType(SavedCardsPage), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('link is ignored while a dialog is open', (t) async {
    await pumpApp(t);
    await emit(t, 'chameleonultra://settings');
    showDialog<void>(
      context: t.element(find.byType(SettingsMainPage)),
      builder: (_) => const AlertDialog(title: Text('dlg')),
    );
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('dlg'), findsOneWidget);
    await emit(t, 'chameleonultra://cards');
    expect(find.text('dlg'), findsOneWidget);
    expect(find.byType(SettingsMainPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(SavedCardsPage, skipOffstage: false), findsNothing);
    await t.pump(const Duration(seconds: 1));
  });

  // Every host must map to the same page index for both schemes.
  // Index: 0 Home/Connect, 1 Slot Manager, 2 Saved Cards, 3 Read, 4 Write,
  // 5 Tools, 6 Plugins, 7 Settings.
  const mapping = <String, int>{
    'settings': 7,
    'home': 0,
    'slots': 1,
    'connect': 0,
    'slot-manager': 1,
    'cards': 2,
    'read': 3,
    'saved-cards': 2,
    'write': 4,
    'tools': 5,
    'plugins': 6,
    'SETTINGS': 7,
  };
  const offlinePages = <int, Type>{
    0: ConnectPage,
    2: SavedCardsPage,
    5: ToolsPage,
    6: PluginsPage,
    7: SettingsMainPage,
  };
  for (final scheme in ['chameleonultra', 'cugui']) {
    testWidgets('$scheme:// maps every host to its page index', (t) async {
      await pumpApp(t);
      final dynamic state = t.state(find.byType(MainPage));
      for (final e in mapping.entries) {
        // Park on a page that is neither the target nor the offline fallback,
        // so a dropped link can never look like a handled one.
        final park = e.value == 7 ? 'tools' : 'settings';
        await emit(t, 'chameleonultra://$park');
        expect(state.selectedIndex, e.value == 7 ? 5 : 7);

        sink!.success('$scheme://${e.key}');
        await t.idle(); // deliver the event; no frame built yet
        // Target chosen by the handler, before build() applies the offline
        // fallback for the device-only pages 1, 3 and 4.
        expect(state.selectedIndex, e.value, reason: '$scheme://${e.key}');
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        // No device in the test: device-only pages fall back to connect.
        final shown = offlinePages[e.value] ?? ConnectPage;
        expect(
          find.byType(shown),
          findsOneWidget,
          reason: '$scheme://${e.key}',
        );
        expect(
          t.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
          offlinePages.containsKey(e.value) ? e.value : 0,
        );
      }
      await emit(t, 'chameleonultra://settings');
      await emit(t, '${scheme.toUpperCase()}://tools'); // scheme any case
      expect(find.byType(ToolsPage), findsOneWidget);
      await emit(t, '$scheme://bogus');
      expect(find.byType(ToolsPage), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('cugui cold start link and other schemes', (t) async {
    launchLinks = ['cugui://settings'];
    await pumpApp(t);
    expect(find.byType(SettingsMainPage), findsOneWidget);
    await emit(t, 'cuguix://cards');
    await emit(t, 'cu://cards');
    await emit(t, 'https://cards');
    expect(find.byType(SettingsMainPage), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });
}
