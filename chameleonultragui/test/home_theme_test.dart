import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/page/home_overview.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/helpers/colors.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _colorNames = [
  'default',
  'purple',
  'blue',
  'green',
  'indigo',
  'lime',
  'red',
  'yellow',
];

late Directory _outDir;
late SharedPreferencesProvider _prefs;
late ChameleonGUIState _appState;

Future<void> _loadFonts() async {
  const candidates = [
    r'C:\Windows\Fonts\segoeui.ttf',
    '/System/Library/Fonts/SFNS.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final loader = FontLoader(
        'TestSans',
      )..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await loader.load();
      break;
    }
  }
  final mono = FontLoader('RobotoMono')
    ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'));
  await mono.load();

  final sep = Platform.pathSeparator;
  final exe = Platform.resolvedExecutable;
  final marker = '${sep}bin${sep}cache${sep}';
  final idx = exe.toLowerCase().indexOf(marker.toLowerCase());
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      (idx > 0 ? exe.substring(0, idx) : null);
  if (root != null) {
    final file = File(
      '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final icons = FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await icons.load();
    }
  }
}

HomeViewData _data() {
  final types = [
    SlotTypes(hf: TagType.mifare1K, lf: TagType.em410X),
    SlotTypes(hf: TagType.ntag215),
    SlotTypes(),
    SlotTypes(hf: TagType.hf14a4),
    SlotTypes(lf: TagType.hidProx),
    SlotTypes(hf: TagType.mifare4K),
    SlotTypes(hf: TagType.ultralight),
    SlotTypes(),
  ];
  final names = List.generate(8, (_) => SlotNames());
  names[0].hf = 'Office';
  names[1].hf = 'Gym';
  names[3].hf = 'Hotel room';
  names[4].lf = 'Garage';
  names[5].hf = 'Apartment building main entrance';
  names[6].hf = 'Membership';
  final enabled = List.generate(8, (_) => EnabledSlotInfo(hf: true, lf: true));
  enabled[5] = EnabledSlotInfo();

  return HomeViewData(
    deviceName: 'Chameleon Ultra',
    device: ChameleonDevice.ultra,
    connectionType: ConnectionType.ble,
    portName: 'SN-000000',
    batteryPercent: 84,
    firmwareVersion: '2.3.0 (abc1234)',
    firmwareCommit: 'abc1234',
    updateAvailable: true,
    isReaderMode: false,
    isDemo: false,
    capabilitiesSupported: true,
    activeSlot: 0,
    slotsReady: true,
    slotTypes: types,
    slotNames: names,
    enabledSlots: enabled,
    recentCards: [
      CardSave(uid: '04A1B2C3D4E5F6', name: 'Office', tag: TagType.mifare1K),
      CardSave(uid: '010203040506', name: 'Gym', tag: TagType.em410X),
      CardSave(
        uid: 'AABBCCDDEEFF001122334455',
        name: 'Membership card with a long name',
        tag: TagType.ntag215,
      ),
    ],
  );
}

ThemeData _theme(Color seed, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
    fontFamily: 'TestSans',
  );
}

Widget _homeShell(GlobalKey boundaryKey, bool rail) {
  final overview = HomeOverview(
    data: _data(),
    loading: false,
    onSelectSlot: (_) {},
    onOpenSavedCards: () {},
    onSettings: () {},
    onDisconnect: () {},
    onToggleReaderMode: () {},
    onUpdate: () {},
    onCopy: (_) {},
  );
  return RepaintBoundary(
    key: boundaryKey,
    child: Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: rail
          ? Row(
              children: [
                SizedBox(
                  width: 80,
                  child: NavigationRail(
                    selectedIndex: 0,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                ),
                Expanded(child: overview),
              ],
            )
          : overview,
    ),
  );
}

Widget _savedPage(GlobalKey boundaryKey) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: _prefs),
      ChangeNotifierProvider.value(value: _appState),
    ],
    child: RepaintBoundary(key: boundaryKey, child: const SavedCardsPage()),
  );
}

Widget _app(Widget home, ThemeData theme) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    darkTheme: theme,
    home: home,
  );
}

Future<ui.Image> _render(
  WidgetTester tester,
  Widget home,
  GlobalKey boundaryKey, {
  required Size size,
  required ThemeData theme,
  Brightness platformBrightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
  await tester.pumpWidget(_app(home, theme));
  await tester.pump();
  await tester.runAsync(() async {
    if (find.byType(HomeOverview).evaluate().isNotEmpty) {
      final context = tester.element(find.byType(HomeOverview));
      await precacheImage(
        const AssetImage('assets/black-ultra-standing-front.webp'),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage(pixelRatio: 1);
}

Future<void> _savePng(WidgetTester tester, ui.Image image, String path) async {
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(data!.buffer.asUint8List());
  });
}

Future<Color> _pixel(WidgetTester tester, ui.Image image, int x, int y) async {
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(
    data!.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void _checkContrast(ColorScheme scheme) {
  final panel = scheme.surfaceContainerLow;
  final page = scheme.surface;
  expect(_contrast(scheme.onSurface, panel), greaterThanOrEqualTo(4.5));
  expect(_contrast(scheme.onSurfaceVariant, panel), greaterThanOrEqualTo(3.0));
  expect(_contrast(scheme.primary, panel), greaterThanOrEqualTo(4.5));
  expect(_contrast(scheme.primary, panel), greaterThanOrEqualTo(3.0));
  expect(_contrast(scheme.outlineVariant, page), greaterThanOrEqualTo(1.3));
}

void _checkNoHardcodedColors() {
  for (final path in [
    'lib/gui/page/home.dart',
    'lib/gui/page/home_overview.dart',
  ]) {
    final text = File(path).readAsStringSync();
    expect(
      RegExp(r'Color\(0x').hasMatch(text),
      isFalse,
      reason: '$path contains a hardcoded Color(0x...)',
    );
  }
}

Future<void> _renderHomeCombo(
  WidgetTester tester,
  int colorIndex,
  Brightness brightness,
) async {
  final size = const Size(1280, 800);
  final theme = _theme(getThemeColor(colorIndex), brightness);
  final homeKey = GlobalKey();
  final image = await _render(
    tester,
    _homeShell(homeKey, true),
    homeKey,
    size: size,
    theme: theme,
  );
  final tag = '${_colorNames[colorIndex]}_${brightness.name}';
  await _savePng(tester, image, '${_outDir.path}/home_$tag.png');

  final points = [
    const Offset(640, 8),
    const Offset(4, 400),
    const Offset(1270, 80),
    const Offset(1270, 790),
    const Offset(350, 790),
  ];
  final background = await _pixel(
    tester,
    image,
    points.first.dx.toInt(),
    points.first.dy.toInt(),
  );
  for (final p in points) {
    final c = await _pixel(tester, image, p.dx.toInt(), p.dy.toInt());
    expect(c, background, reason: 'home background differs at $p ($tag)');
  }

  final savedKey = GlobalKey();
  final savedImage = await _render(
    tester,
    _savedPage(savedKey),
    savedKey,
    size: size,
    theme: theme,
  );
  await _savePng(tester, savedImage, '${_outDir.path}/saved_$tag.png');
  final savedBg = await _pixel(tester, savedImage, 2, 798);
  expect(
    savedBg,
    background,
    reason: 'home and saved-cards backgrounds differ ($tag)',
  );

  _checkContrast(theme.colorScheme);
}

Future<void> _renderHomeSize(
  WidgetTester tester,
  ThemeMode mode,
  Size size,
  String name,
) async {
  final brightness = mode == ThemeMode.dark
      ? Brightness.dark
      : Brightness.light;
  final theme = _theme(getThemeColor(0), brightness);
  final key = GlobalKey();
  final image = await _render(
    tester,
    _homeShell(key, false),
    key,
    size: size,
    theme: theme,
    platformBrightness: brightness,
  );
  await _savePng(
    tester,
    image,
    '${_outDir.path}/home_default_${mode.name}_$name.png',
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    _prefs = SharedPreferencesProvider();
    await _prefs.load();
    _appState = ChameleonGUIState(_prefs);
    _outDir = Directory(
      '${Directory.systemTemp.path}/chameleon_home_theme_goldens',
    );
    if (_outDir.existsSync()) {
      _outDir.deleteSync(recursive: true);
    }
    _outDir.createSync(recursive: true);
    _checkNoHardcodedColors();
  });

  testWidgets('home theme combinations', skip: !Platform.isWindows, (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    for (var i = 0; i < _colorNames.length; i++) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await _renderHomeCombo(tester, i, brightness);
      }
    }
  });

  testWidgets(
    'home default color by mode and size',
    skip: !Platform.isWindows,
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      for (final mode in ThemeMode.values) {
        await _renderHomeSize(tester, mode, const Size(800, 800), '800x800');
        await _renderHomeSize(tester, mode, const Size(390, 844), '390x844');
      }
    },
  );
}
