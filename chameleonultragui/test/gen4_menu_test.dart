import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/gen4.dart';
import 'package:chameleonultragui/helpers/mifare_classic/gen4.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/gen4_device.dart';

void main() {
  testWidgets(
    'read, edit, confirm and verify configuration with a new password',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final device = Gen4TestDevice();
      await tester.pumpWidget(
        ChangeNotifierProvider<ChameleonGUIState>.value(
          value: gen4TestState(device),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: Gen4Menu()),
          ),
        ),
      );
      expect(find.text('Apply configuration'), findsNothing);
      await tester.tap(find.text('Read configuration'));
      await tester.pumpAndSettle();
      expect(device.reader, isTrue);
      expect(find.text('Apply configuration').hitTestable(), findsOneWidget);
      final password = find.widgetWithText(
        TextFormField,
        'New backdoor password (4 bytes)',
      );
      await tester.ensureVisible(password);
      await tester.enterText(password, 'AABBCCDD');
      final apply = find.text('Apply configuration');
      expect(apply.hitTestable(), findsOneWidget);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(device.commands.where((c) => c[5] == 0xF0), isEmpty);
      await tester.tap(find.text('Confirm write'));
      await tester.pumpAndSettle();
      expect(gen4Hex(device.config.sublist(2, 6)), 'AABBCCDD');
      expect(gen4Hex(device.commands.last.sublist(0, 6)), 'CFAABBCCDDC6');
      expect(find.text('Write verified by readback.'), findsOneWidget);
      expect(device.commands.where((c) => c[5] == 0xF1), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('permanent lock requires its own explicit confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final device = Gen4TestDevice();
    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: gen4TestState(device),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Gen4Menu()),
        ),
      ),
    );
    await tester.tap(find.text('Read configuration'));
    await tester.pumpAndSettle();
    final section = find.text('Permanently lock configuration');
    await tester.ensureVisible(section);
    await tester.tap(section);
    await tester.pumpAndSettle();
    final lock = find.widgetWithText(
      TextButton,
      'Permanently lock configuration',
    );
    await tester.ensureVisible(lock);
    await tester.tap(lock);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNWidgets(2));
    expect(find.text('Lock permanently'), findsOneWidget);
    expect(device.commands.where((c) => c[5] == 0xF1), isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(device.commands.where((c) => c[5] == 0xF1), isEmpty);
    await tester.tap(lock);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock permanently'));
    await tester.pumpAndSettle();
    expect(device.commands.where((c) => c[5] == 0xF1), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final revision in ['00000006A0', '00000003AB', '3F']) {
    testWidgets('PACK address selection for CC $revision', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final device = Gen4TestDevice()..version = gen4ParseHex(revision);
      device.config[0] = 1;
      device.config[1] = 1;
      await tester.pumpWidget(
        ChangeNotifierProvider<ChameleonGUIState>.value(
          value: gen4TestState(device),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: Gen4Menu()),
          ),
        ),
      );
      await tester.tap(find.text('Read configuration'));
      await tester.pumpAndSettle();
      final advanced = find.text('UID and advanced memory access');
      await tester.ensureVisible(advanced);
      await tester.tap(advanced);
      await tester.pumpAndSettle();
      final setting = find.widgetWithText(
        DropdownButtonFormField<int>,
        'Memory-backed setting',
      );
      await tester.ensureVisible(setting);
      await tester.tap(setting);
      await tester.pumpAndSettle();
      await tester.tap(find.text('02 · PACK').last);
      await tester.pumpAndSettle();
      final read = find.text('Read setting');
      await tester.ensureVisible(read);
      if (revision == '3F') {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Read setting'),
              )
              .onPressed,
          isNull,
        );
        final page = find.widgetWithText(
          DropdownButtonFormField<int>,
          'PACK page',
        );
        await tester.ensureVisible(page);
        await tester.tap(page);
        await tester.pumpAndSettle();
        await tester.tap(find.text('E6').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(read);
      }
      expect(
        find.text(revision == '00000006A0'
            ? '2 hex bytes, starting at block 13.'
            : '2 hex bytes, starting at block E6.'),
        findsOneWidget,
      );
      await tester.tap(read);
      await tester.pumpAndSettle();
      expect(
        gen4Hex(device.commands.last.sublist(5)),
        revision == '00000006A0' ? 'CE13' : 'CEE6',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
