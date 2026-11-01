import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';

import 'sl1_profile_test.dart' show fixture;
import 'sl1_card_workflows_test.dart' show appFor, host;

void main() {
  for (final uidBytes in [4, 7]) {
    testWidgets(
      'approved $uidBytes-byte UID patch preserves partial canonical tail and errors',
      (tester) async {
        final profile = fixture(type: '1k');
        profile.json['hf14a']['uid'] = uidBytes == 4
            ? '01020304'
            : '01020304050607';
        final tail = '${'AA' * (uidBytes == 4 ? 7 : 5)}??';
        profile.json['classic']['blocks'][0] = {
          'data':
              '${uidBytes == 4 ? '0102030404080400' : '01020304050607080400'}$tail',
          'status': 'read',
          'key': 'B',
          'errors': [
            {'key': 'A', 'status': 6, 'reason': 'Synthetic read error'},
          ],
        };
        profile.json['cardAuth']['verification'] = {
          'status': 'verified',
          'evidence': 'Synthetic original binding',
        };
        final card = sl1ToCard(profile);
        final app = await appFor(card);
        final key = GlobalKey<CardEditMenuState>();
        await tester.pumpWidget(
          host(
            app,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => CardEditMenu(key: key, tagSave: card),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final newUid = uidBytes == 4 ? '11223344' : '11223344556677';
        key.currentState!.uidController.text = bytesToHexSpace(
          Sl1Profile.bytes(newUid),
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes'));
        await tester.pumpAndSettle();
        final saved = app.sharedPreferencesProvider.getCards().single;
        final exported = Sl1Profile.parse(exportSl1Card(saved));
        final expectedPrefix = uidBytes == 4
            ? '1122334444080400'
            : '11223344556677080400';
        expect(
          exported.json['classic']['blocks'][0]['data'],
          '$expectedPrefix$tail',
        );
        expect(saved.data[0], isEmpty);
        expect(
          exported.json['classic']['blocks'][0]['errors'],
          profile.json['classic']['blocks'][0]['errors'],
        );
        expect(exported.json['classic']['provenance'], 'legacy-unverified');
        expect(exported.json['cardAuth']['enabled'], isFalse);
        expect(exported.json['cardAuth']['verification'], {
          'status': 'provided',
          'evidence': null,
        });
        expect(() => exported.image(), throwsFormatException);
      },
    );
    testWidgets(
      'cancelled $uidBytes-byte partial identity edit retains original record',
      (tester) async {
        final profile = fixture(type: '1k');
        profile.json['hf14a']['uid'] = uidBytes == 4
            ? '01020304'
            : '01020304050607';
        profile.json['classic']['blocks'][0]['data'] = '${'AA' * 15}??';
        final card = sl1ToCard(profile);
        final original = card.toJson();
        final app = await appFor(card);
        final key = GlobalKey<CardEditMenuState>();
        await tester.pumpWidget(
          host(
            app,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => CardEditMenu(key: key, tagSave: card),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        key.currentState!.uidController.text = uidBytes == 4
            ? '11 22 33 44'
            : '11 22 33 44 55 66 77';
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          app.sharedPreferencesProvider.getCards().single.toJson(),
          original,
        );
      },
    );
  }
}
