import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/create.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const payload = '2A 00 00 00 FF 00 00 00 FF FF 00 03 84';

  Future<SharedPreferencesProvider> pumpDialog(
    WidgetTester tester,
    Widget dialog,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ChameleonGUIState(preferences),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: dialog),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return preferences;
  }

  testWidgets('create a HID ACTProx card using firmware format ID 42', (
    tester,
  ) async {
    final preferences = await pumpDialog(tester, const CardCreateMenu());
    await tester.tap(find.byType(DropdownButton<TagType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HID Prox').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    final option = find.text('HID ACTProx 36-bit');
    await tester.scrollUntilVisible(
      option,
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(option);
    await tester.pumpAndSettle();
    final state = tester.state<CardCreateMenuState>(
      find.byType(CardCreateMenu),
    );
    expect(state.hidTypeController.text, '42');
    state.nameController.text = 'ACTProx';
    state.uidController.text = '00 00 00 FF FF';
    state.facilityCodeController.text = '255';
    state.issueLevelController.text = '0';
    state.oemController.text = '900';
    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();
    expect(preferences.getCards().single.uid, payload);
  });

  testWidgets('open and save a scanned ACTProx card without changing its ID', (
    tester,
  ) async {
    final preferences = await pumpDialog(
      tester,
      CardEditMenu(
        tagSave: CardSave(name: 'ACTProx', tag: TagType.hidProx, uid: payload),
        isNew: true,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('HID ACTProx 36-bit'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect(dropdown.value, 42);
    expect(dropdown.items!.map((item) => item.value), [
      ...List.generate(30, (index) => index + 1),
      42,
    ]);
    preferences.setCards([
      tester.widget<CardEditMenu>(find.byType(CardEditMenu)).tagSave,
    ]);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(preferences.getCards().single.uid, payload);
  });

  test('ACTProx scan payload displays and round-trips as HID format 42', () {
    // Same >BIBIBH layout as the firmware/CLI: format, FC, CN, IL, OEM.
    const payload = '2A 00 00 00 FF 00 00 00 FF FF 00 03 84';
    final card = HIDCard.fromUID(payload);

    expect(card.hidType, 42);
    expect(card.facilityCode, 255);
    expect(card.oem, 900);
    expect(
      card.toViewableString(),
      '65535 (00 00 00 FF FF, HID ACTProx 36-bit, FC: 255, OEM: 900)',
    );
    expect(card.toString(), payload);
    expect(getLFCardFromUID(TagType.hidProx, payload).toString(), payload);
  });
}
