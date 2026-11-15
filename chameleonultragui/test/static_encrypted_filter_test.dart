import 'dart:math';

import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seed membership matches pairwise filtering, preserving order and duplicates', () {
    final random = Random(42);
    final cases = <(List<int>, List<int>, int, int)>[
      ([], [], 0, 0),
      ([0, 0xffffffffffff], [], 0, 0),
      ([], [0, 0xffffffffffff], 0, 0),
      ([0, 0, 1, 0xffffffffffff], [1, 0, 0, 1], 0, 0),
    ];
    for (var i = 0; i < 100; i++) {
      final a = List.generate(25, (_) => random.nextInt(1 << 24));
      final b = [...a.reversed.take(10), ...a.take(5), 0xffffffffffff];
      cases.add((a, b, random.nextInt(1 << 32), random.nextInt(1 << 32)));
      cases.add((a, b, 0x82d91e42, 0x82d91e42));
    }
    for (final (a, b, ntA, ntB) in cases) {
      final expectedA = [
        for (final key in a)
          if (StaticEncryptedKeysFilter.findMatchingKeys(
            ntA,
            key,
            ntB,
            b,
          ).isNotEmpty)
            key,
      ];
      final expectedB = [
        for (final key in b)
          if (StaticEncryptedKeysFilter.findMatchingKeys(
            ntB,
            key,
            ntA,
            a,
          ).isNotEmpty)
            key,
      ];
      final actual = StaticEncryptedKeysFilter.filterKeys(a, b, ntA, ntB);
      expect(actual.$1, expectedA);
      expect(actual.$2, expectedB);
    }
  });
}
