import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'sl1_profile_test.dart' show fixture;

CardSave verifiedCard() {
  final card = sl1ToCard(fixture());
  card.sl1Profile!.json['cardAuth']['verification'] = {
    'status': 'verified',
    'evidence': 'Synthetic original binding',
  };
  return card;
}

void main() {
  final changes = <String, void Function(CardSave)>{
    'UID': (card) => card.uid = '11223344',
    'ATQA': (card) => card.atqa = Sl1Profile.bytes('1234'),
    'SAK': (card) => card.sak = 9,
    'ATS': (card) => card.ats = Sl1Profile.bytes('037580'),
    'memory': (card) => card.data[0][0] ^= 1,
  };
  for (final change in changes.entries) {
    test('${change.key} edit disables CardAuth and preserves key locally', () {
      final card = verifiedCard();
      final originalKey = card.sl1Profile!.json['cardAuth']['key'];
      change.value(card);
      reconcileSl1(card, memoryChanged: change.key == 'memory');
      final auth = card.sl1Profile!.json['cardAuth'];
      expect(auth['enabled'], isFalse);
      expect(auth['key'], originalKey);
      expect(auth['verification'], {'status': 'provided', 'evidence': null});
    });
  }
  for (final cancel in [false, true]) {
    testWidgets(
      cancel
          ? 'cancelled identity edit preserves original enabled binding'
          : 'name-only edit preserves enabled verified binding',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = SharedPreferencesProvider();
        await preferences.load();
        final card = verifiedCard();
        preferences.setCards([card]);
        final original = card.toJson();
        final app = ChameleonGUIState(preferences)
          ..log = Logger(level: Level.off);
        final key = GlobalKey<CardEditMenuState>();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: app,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => CardEditMenu(key: key, tagSave: card),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        key.currentState!.nameController.text = 'Explicit rename';
        if (cancel) {
          key.currentState!.uidController.text = '11 22 33 44';
        }
        await tester.tap(find.text(cancel ? 'Cancel' : 'Save'));
        await tester.pumpAndSettle();
        final saved = preferences.getCards().single;
        if (cancel) {
          expect(saved.toJson(), original);
        } else {
          expect(saved.name, 'Explicit rename');
        }
        expect(saved.sl1Profile!.json['cardAuth']['enabled'], isTrue);
        expect(saved.sl1Profile!.json['cardAuth']['verification'], {
          'status': 'verified',
          'evidence': 'Synthetic original binding',
        });
      },
    );
  }
}
