import 'package:chameleonultragui/helpers/t55xx/write/base.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Each read returns the next value; null is a read that found no tag.
  Future<Object?> Function() reads(List<String?> values, List<int> count) {
    return () async => values[count[0]++];
  }

  test('match on the first read: one read', () async {
    final count = [0];
    expect(
      await t55xxReadBack(
        reads(["1122334455"], count),
        "1122334455",
        delay: Duration.zero,
      ),
      isTrue,
    );
    expect(count[0], 1);
  });

  test('a missed read, then a match: written', () async {
    final count = [0];
    expect(
      await t55xxReadBack(
        reads([null, "1122334455"], count),
        "1122334455",
        delay: Duration.zero,
      ),
      isTrue,
    );
    expect(count[0], 2);
  });

  test('three reads without a match: failed', () async {
    final count = [0];
    expect(
      await t55xxReadBack(
        reads([null, "aabbccddee", "aabbccddee"], count),
        "1122334455",
        delay: Duration.zero,
      ),
      isFalse,
    );
    expect(count[0], 3);
  });
}
