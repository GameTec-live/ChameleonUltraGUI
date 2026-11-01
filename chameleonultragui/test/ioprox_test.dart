import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/create.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const payload = '01 53 30 39 00 78 54 E0 33 09 CD 4B 00 00 00 00';

  test('ioProx composition matches firmware XSF vectors', () {
    // Generated independently with firmware ioprox_encode_params_to_data.
    for (final vector in [
      (1, 83, 12345, payload),
      (0, 0, 0, '00 00 00 00 00 78 40 20 10 08 04 3F 00 00 00 00'),
      (255, 255, 65535, 'FF FF FF FF 00 78 7F FF FF FF FC 4F 00 00 00 00'),
    ]) {
      final card = IoProxCard.fromFields(
          version: vector.$1, facilityCode: vector.$2, cardNumber: vector.$3);
      expect(card.toString(), vector.$4);
    }
    expect(
        () =>
            IoProxCard.fromFields(version: 256, facilityCode: 0, cardNumber: 0),
        throwsRangeError);
    expect(
        () =>
            IoProxCard.fromFields(version: 0, facilityCode: -1, cardNumber: 0),
        throwsRangeError);
    expect(
        () => IoProxCard.fromFields(
            version: 0, facilityCode: 0, cardNumber: 65536),
        throwsRangeError);
  });

  test('saved ioProx identities display fields and preserve the full payload',
      () {
    final saved = CardSave.fromJson(
        CardSave(name: 'ioProx', tag: TagType.ioProx, uid: payload).toJson());
    final card = getLFCardFromUID(saved.tag, saved.uid) as IoProxCard;
    expect((card.version, card.facilityCode, card.cardNumber), (1, 83, 12345));
    expect(card.toViewableString(), '12345 (Version: 1, FC: 83, $payload)');
    expect(card.toString(), payload);
    final reserved =
        IoProxCard.fromUID(payload.replaceFirst('00 00 00 00', 'AA BB CC DD'));
    expect(reserved.toString(), endsWith('AA BB CC DD'));
  });

  test('short imported ioProx identities retain their raw display', () {
    for (final uid in ['', '01', '01 53', '01 53 30']) {
      final imported = CardSave.fromJson(
          CardSave(name: 'Short ioProx', tag: TagType.ioProx, uid: uid).toJson());
      final card = getLFCardFromUID(imported.tag, imported.uid);
      expect(card.toViewableString(), uid);
    }
  });

  testWidgets('create ioProx offline with required decimal fields and bounds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ChameleonGUIState(preferences),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CardCreateMenu(folderId: 'folder')),
      ),
    ));
    final state =
        tester.state<CardCreateMenuState>(find.byType(CardCreateMenu));
    await tester.tap(find.byType(DropdownButton<TagType>));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ioProx').last, 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('ioProx').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'UID'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Version'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Facility Code'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Card number'), findsOneWidget);
    state.nameController.text = 'ioProx';
    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();
    expect(preferences.getCards(), isEmpty);
    for (final values in [
      ('256', '83', '12345'),
      ('1', '256', '12345'),
      ('1', '83', '65536')
    ]) {
      state.ioProxVersionController.text = values.$1;
      state.ioProxFacilityCodeController.text = values.$2;
      state.ioProxCardNumberController.text = values.$3;
      await tester.tap(find.text('Create').last);
      await tester.pumpAndSettle();
      expect(preferences.getCards(), isEmpty);
    }
    state.ioProxCardNumberController.text = '12345';
    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();
    final saved = preferences.getCards().single;
    expect(saved.uid, payload);
    expect(saved.folderId, 'folder');
    expect(saved.tag, TagType.ioProx);
    expect(tester.takeException(), isNull);
  });
}
