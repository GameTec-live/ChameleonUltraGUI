import 'package:chameleonultragui/gui/mobile/mobile_shell.dart';
import 'package:chameleonultragui/gui/mobile/platform_selector.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Goes through the real app entry point to check which interface is chosen.
Future<void> pumpApp(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'emulate_device': true,
    'auto_scan_enabled': false,
  });
  final provider = SharedPreferencesProvider();
  await provider.load();

  await tester.pumpWidget(ChameleonGUI(provider));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  tearDown(() => debugUiModeOverride = null);

  testWidgets(
    'desktop keeps the navigation rail, even in a phone sized window',
    (tester) async {
      await pumpApp(tester, const Size(360, 640));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(MobileShell), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('phones get the mobile shell with bottom navigation', (
    tester,
  ) async {
    debugUiModeOverride = UiMode.mobile;
    await pumpApp(tester, const Size(390, 844));

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
