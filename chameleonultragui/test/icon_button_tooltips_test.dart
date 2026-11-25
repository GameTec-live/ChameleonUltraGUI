import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/view.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('every icon button in the saved card view has a tooltip', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesProvider();
    await prefs.load();
    final card = CardSave(
      uid: '04 11 22 33 44 55 66',
      name: 'Badge',
      tag: TagType.ntag215,
      atqa: Uint8List.fromList([0x00, 0x44]),
      extraData: CardSaveExtra(
        ultralightVersion: Uint8List(8),
        ultralightSignature: Uint8List(32),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ChameleonGUIState(prefs),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CardViewMenu(tagSave: card, onMove: (CardSave _) async {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(buttons, isNotEmpty);
    expect([for (final b in buttons) b.tooltip], everyElement(isNotNull));
    expect(find.byTooltip('Duplicate card'), findsOneWidget);
  });
}
