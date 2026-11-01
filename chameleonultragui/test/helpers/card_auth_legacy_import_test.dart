import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';

import 'sl1_profile_test.dart' show fixture;

void main() {
  final suppliedKey = Sl1Profile.encodeBytes(List.generate(16, (i) => i));

  test(
    'manual CardAuth entry validates a complete legacy image as imported',
    () {
      final card = sl1ToCard(fixture())..sl1Profile = null;
      final expected = card.data.map((b) => b.toList()).toList();
      updateCardAuthKey(card, suppliedKey);
      final profile = card.sl1Profile!;
      expect(profile.json['classic']['provenance'], 'imported');
      expect(profile.image(), expected);
      expect(
        profile.json['classic']['keys'].every(
          (s) => s['a']['status'] == 'unknown' && s['b']['status'] == 'unknown',
        ),
        isTrue,
      );
      updateCardAuthKey(card, '');
      expect(card.sl1Profile!.json['cardAuth'], isNull);
      expect(card.sl1Profile!.image(), expected);
    },
  );

  for (final invalidAccess in [false, true]) {
    test(
      'invalid legacy input does not replace the usable archive, access=$invalidAccess',
      () {
        final card = sl1ToCard(fixture())..sl1Profile = null;
        if (invalidAccess) {
          card.data[3] = Uint8List.fromList(card.data[3])..fillRange(6, 9, 0);
        } else {
          card.data[1] = Uint8List(0);
        }
        final expected = card.data.map((b) => b.toList()).toList();
        expect(
          () => updateCardAuthKey(card, suppliedKey),
          throwsFormatException,
        );
        expect(card.sl1Profile, isNull);
        expect(card.data, expected);
      },
    );
  }

  test('manual key edits never promote attached partial coverage', () {
    final profile = fixture();
    profile.json['classic']['blocks'][1]['data'] = '??' * 16;
    profile.json['classic']['blocks'][1]['status'] = 'unread';
    final card = sl1ToCard(profile);
    updateCardAuthKey(card, suppliedKey);
    expect(card.sl1Profile!.json['classic']['blocks'][1]['data'], '??' * 16);
    expect(() => card.sl1Profile!.image(), throwsFormatException);
  });
}
