import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/sl1_profile_status.dart';

import 'sl1_routes_test.dart' show ProfileRouteDevice;

class StagedProfileDevice extends ProfileRouteDevice {
  int received = 20;
  int expected = 20;
  bool staged = true;
  int saveStatus = 0x68;
  int extraFlags = 0;
  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    final response = await super.sendCmd(
      cmd,
      data: data,
      timeout: timeout,
      skipReceive: skipReceive,
      firstRun: firstRun,
    );
    if (cmd == ChameleonCommand.sl1Status) {
      response!.data = Uint8List.fromList([
        1,
        data![1],
        (staged ? 8 : 0) | extraFlags,
        3,
        232,
        1,
        0x90,
        4,
        received >> 8,
        received & 255,
        expected >> 8,
        expected & 255,
        0x68,
        1,
      ]);
    } else if (cmd == ChameleonCommand.sl1Save) {
      response!.status = saveStatus;
      if (saveStatus == 0x68) {
        staged = false;
        extraFlags &= ~0x40;
      }
    }
    return response;
  }
}

void main() {
  test(
    'explicit staged save checks coverage and mode before selected-slot SAVE',
    () async {
      final device = StagedProfileDevice();
      await device.sl1Uploader.save(3);
      expect(device.reader, isFalse);
      expect(
        device.calls.indexOf(ChameleonCommand.changeDeviceMode.value),
        lessThan(device.calls.indexOf(4048)),
      );
      expect(device.payloads[device.calls.indexOf(4048)], [1, 3]);
      expect(device.calls.where((c) => c == 4048), hasLength(1));
    },
  );
  test('incomplete, absent, malformed geometry and unsupported stages do not mutate', () async {
    for (final device in [
      StagedProfileDevice()..received = 19,
      StagedProfileDevice()..staged = false,
      StagedProfileDevice()
        ..expected = 19
        ..received = 19,
    ]) {
      await expectLater(device.sl1Uploader.save(3), throwsStateError);
      expect(
        device.calls,
        isNot(contains(ChameleonCommand.getDeviceMode.value)),
      );
      expect(device.calls, isNot(contains(4048)));
    }
    final unsupported = StagedProfileDevice()..supported = false;
    await expectLater(unsupported.sl1Uploader.save(3), throwsUnsupportedError);
    expect(unsupported.calls, [ChameleonCommand.getDeviceCapabilities.value]);
  });
  testWidgets(
    'status exposes Save only for complete stage and surfaces numeric failure once',
    (tester) async {
      final device = StagedProfileDevice()..saveStatus = 0x66;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Sl1SlotDialog(slot: 3, uploader: device.sl1Uploader),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save staged profile'), findsOneWidget);
      await tester.tap(find.text('Save staged profile'));
      await tester.pumpAndSettle();
      expect(find.textContaining('status 102'), findsOneWidget);
      expect(find.text('Save staged profile'), findsOneWidget);
      expect(device.calls.where((c) => c == 4048), hasLength(1));
      final incomplete = StagedProfileDevice()..received = 19;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Sl1SlotDialog(
            key: UniqueKey(),
            slot: 3,
            uploader: incomplete.sl1Uploader,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save staged profile'), findsNothing);
    },
  );
  testWidgets(
    'stale-only and unknown future flags do not imply incomplete save',
    (tester) async {
      final device = StagedProfileDevice()
        ..staged = false
        ..extraFlags = 0x90;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Sl1SlotDialog(slot: 3, uploader: device.sl1Uploader),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Enable', 'Disable', 'Clear CardAuth']) {
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, label))
              .onPressed,
          isNotNull,
        );
      }
      expect(find.textContaining('Incomplete save: false'), findsOneWidget);
      expect(
        find.textContaining('Stale/corrupt binding: true'),
        findsOneWidget,
      );
      expect(find.textContaining('Raw status: 010390'), findsOneWidget);
      expect(
        device.calls.every(
          (c) =>
              [ChameleonCommand.getDeviceCapabilities.value, 4045].contains(c),
        ),
        isTrue,
      );
      await tester.tap(find.text('Clear CardAuth'));
      await tester.pumpAndSettle();
      expect(device.calls.where((c) => c == 4050), hasLength(1));
    },
  );
  testWidgets(
    'incomplete save blocks persistent controls but retains volatile cancel and refresh',
    (tester) async {
      final device = StagedProfileDevice()
        ..staged = false
        ..extraFlags = 0x40;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Sl1SlotDialog(slot: 3, uploader: device.sl1Uploader),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Enable', 'Disable', 'Clear CardAuth']) {
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, label))
              .onPressed,
          isNull,
        );
      }
      expect(
        find.textContaining('An incomplete profile save is pending.'),
        findsOneWidget,
      );
      expect(find.text('Save staged profile'), findsNothing);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(
        device.calls.every(
          (c) =>
              [ChameleonCommand.getDeviceCapabilities.value, 4045].contains(c),
        ),
        isTrue,
      );
      await tester.tap(find.text('Cancel staged upload'));
      await tester.pumpAndSettle();
      expect(device.calls.where((c) => c == 4049), hasLength(1));
      expect(device.calls.any((c) => [4048, 4050, 4051].contains(c)), isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Clear CardAuth'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'complete staged recovery requires one explicit save and preserves future flags',
    (tester) async {
      final device = StagedProfileDevice()..extraFlags = 0xc0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Sl1SlotDialog(slot: 3, uploader: device.sl1Uploader),
        ),
      );
      await tester.pumpAndSettle();
      expect(device.calls, isNot(contains(4048)));
      expect(find.text('Save staged profile'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Enable'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Save staged profile'));
      await tester.pumpAndSettle();
      expect(device.calls.where((c) => c == 4048), hasLength(1));
      expect(device.calls.any((c) => [4050, 4051].contains(c)), isFalse);
      expect(find.textContaining('Incomplete save: false'), findsOneWidget);
      expect(find.textContaining('Raw status: 010380'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Enable'))
            .onPressed,
        isNotNull,
      );
    },
  );
}
