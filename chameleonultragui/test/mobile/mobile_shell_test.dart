import 'package:chameleonultragui/gui/mobile/controllers/device_controller.dart';
import 'package:chameleonultragui/gui/mobile/mobile_shell.dart';
import 'package:chameleonultragui/gui/mobile/pages/connection_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/device_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/dfu_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'harness.dart';

void main() {
  const phones = {
    'small 320x568': Size(320, 568),
    'landscape 844x390': Size(844, 390),
  };

  group('disconnected', () {
    testWidgets('shows the device list without overflow on a small phone', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(320, 568));
      final appState = await createAppState();

      await tester.pumpWidget(buildMobileApp(appState, textScale: 1.5));
      await settle(tester);

      expect(find.byType(MobileConnectionPage), findsOneWidget);
      expect(find.text('Chameleon Ultra'), findsOneWidget);
      expect(find.text('Demo'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('Read needs a device but Cards and More stay available', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await createAppState();

      await tester.pumpWidget(buildMobileApp(appState));
      await settle(tester);

      await tester.tap(find.text('Read'));
      await tester.pump();
      expect(
        find.text('Connect a Chameleon to use this feature'),
        findsOneWidget,
      );

      await tester.tap(find.text('Go to Device'));
      await tester.pump();
      expect(find.byType(MobileConnectionPage), findsOneWidget);

      await tester.tap(find.text('Cards'));
      await tester.pump();
      expect(find.text('No saved cards yet'), findsOneWidget);

      await tester.tap(find.text('More'));
      await tester.pump();
      expect(find.text('Dictionary download'), findsOneWidget);
      expect(find.text('HF sniffing'), findsOneWidget);
      expect(find.text('LF sniffing'), findsOneWidget);
      // Device-only tools are present but flagged.
      expect(find.textContaining('Device required'), findsWidgets);

      await unmount(tester);
    });

    testWidgets('system back from another tab returns to Device', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await createAppState();

      await tester.pumpWidget(buildMobileApp(appState));
      await settle(tester);

      await tester.tap(find.text('More'));
      await tester.pump();
      expect(find.text('Dictionary download'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byType(MobileConnectionPage), findsOneWidget);
      await unmount(tester);
    });
  });

  group('connected (emulated device)', () {
    testWidgets('tapping the device connects and shows the dashboard', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await createAppState();

      await tester.pumpWidget(buildMobileApp(appState));
      await settle(tester);

      await tester.tap(find.text('Chameleon Ultra'));
      await settle(tester);

      expect(appState.connector!.connected, isTrue);
      expect(find.byType(MobileDevicePage), findsOneWidget);
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    for (final entry in phones.entries) {
      testWidgets(
        'dashboard has no overflow on ${entry.key} at text scale 1.5',
        (tester) async {
          setPhoneSize(tester, entry.value);
          final appState = await createAppState();

          await tester.pumpWidget(buildMobileApp(appState, textScale: 1.5));
          await connectEmulator(tester, appState);

          expect(find.byType(MobileDevicePage), findsOneWidget);
          expect(tester.takeException(), isNull);

          await unmount(tester);
        },
      );
    }

    testWidgets('device data is requested once, not on every rebuild', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await createAppState(
        connector: (log) => CountingSerial(log: log),
      );
      final counting = appState.connector! as CountingSerial;

      await tester.pumpWidget(buildMobileApp(appState));
      await connectEmulator(tester, appState);
      final afterLoad = counting.writes;
      expect(afterLoad, greaterThan(0));

      for (var i = 0; i < 5; i++) {
        appState.changesMade();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('More'));
      await tester.pump();
      await tester.tap(find.text('Device'));
      await tester.pump();

      expect(counting.writes, afterLoad);
      await unmount(tester);
    });

    testWidgets('disconnecting returns to the connection list', (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await createAppState();

      await tester.pumpWidget(buildMobileApp(appState));
      await connectEmulator(tester, appState);
      expect(find.byType(MobileDevicePage), findsOneWidget);

      await appState.disconnect(manual: true);
      await settle(tester);

      expect(find.byType(MobileConnectionPage), findsOneWidget);
      final device = tester
          .element(find.byType(MobileShell))
          .read<MobileDeviceController>();
      expect(device.isConnected, isFalse);
      expect(device.state, DeviceLoadState.idle);

      await unmount(tester);
    });
  });

  group('DFU', () {
    testWidgets('hides navigation and shows flashing progress', (tester) async {
      setPhoneSize(tester, const Size(320, 568));
      final appState = await createAppState();
      final connector = appState.connector!;
      await connector.connectSpecificDevice('Demo');
      connector.isDFU = true;
      appState.progress = 0.4;

      await tester.pumpWidget(buildMobileApp(appState));
      await tester.pump();

      expect(find.byType(MobileDfuPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.4,
      );
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });
}
