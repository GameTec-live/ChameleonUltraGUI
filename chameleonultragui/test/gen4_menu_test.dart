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
      expect(find.text('Apply configuration'), findsOneWidget);
      final password = find.widgetWithText(
        TextFormField,
        'New backdoor password (4 bytes)',
      );
      await tester.ensureVisible(password);
      await tester.enterText(password, 'AABBCCDD');
      final apply = find.text('Apply configuration');
      await tester.ensureVisible(apply);
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
}
