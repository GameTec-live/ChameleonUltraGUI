import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/page/home_overview.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final loader = FontLoader('TestSans')
        ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await loader.load();
      break;
    }
  }
  final mono = FontLoader('RobotoMono')
    ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf'));
  await mono.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final iconCandidates = [
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    '/usr/local/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ];
  for (final path in iconCandidates) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await icons.load();
      break;
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
      CardSave(
        uid: '04A1B2C3D4E5F6',
        name: 'Office',
        tag: TagType.mifare1K,
      ),
      CardSave(
        uid: '010203040506',
        name: 'Gym',
        tag: TagType.em410X,
      ),
      CardSave(
        uid: 'AABBCCDDEEFF001122334455',
        name: 'Membership card with a long name',
        tag: TagType.ntag215,
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        fontFamily: 'TestSans',
      ),
      home: Scaffold(
        body: HomeOverview(
          data: _data(),
          loading: false,
          onSelectSlot: (_) {},
          onOpenSavedCards: () {},
          onSettings: () {},
          onDisconnect: () {},
          onToggleReaderMode: () {},
          onUpdate: () {},
          onCopy: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(HomeOverview));
    await precacheImage(
      const AssetImage('assets/black-ultra-standing-front.webp'),
      context,
    );
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('home at 1280x800', (tester) async {
    await _pump(tester, const Size(1280, 800));
    await expectLater(
      find.byType(HomeOverview),
      matchesGoldenFile('goldens/home_1280x800.png'),
    );
  });

  testWidgets('home at 800x800', (tester) async {
    await _pump(tester, const Size(800, 800));
    await expectLater(
      find.byType(HomeOverview),
      matchesGoldenFile('goldens/home_800x800.png'),
    );
  });

  testWidgets('home at 390x844', (tester) async {
    await _pump(tester, const Size(390, 844));
    await expectLater(
      find.byType(HomeOverview),
      matchesGoldenFile('goldens/home_390x844.png'),
    );
  });
}
