import 'dart:typed_data';

import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mfClassicGenerateFirstBlock', () {
    test('keeps SAK as-is and stores ATQA reversed (4-byte UID)', () {
      // SAK 08 / ATQA 0004 must land as SAK 08 and ATQA bytes 04 00,
      // matching the write-side block 0, not 88 00 04.
      final block0 = mfClassicGenerateFirstBlock(
          Uint8List.fromList([0x82, 0xB9, 0x4F, 0x4B]),
          0x08,
          Uint8List.fromList([0x00, 0x04]));
      expect(block0.length, 16);
      expect(block0.sublist(0, 4), [0x82, 0xB9, 0x4F, 0x4B]); // UID
      expect(block0[4], 0x3F); // BCC = 0x82 ^ 0xB9 ^ 0x4F ^ 0x4B
      expect(block0[5], 0x08); // SAK, not 0x88
      expect(block0.sublist(6, 8), [0x04, 0x00]); // ATQA reversed
    });

    test('a genuine zero UID rebuilds to a zero UID', () {
      final block0 = mfClassicGenerateFirstBlock(
          Uint8List(4), 0x08, Uint8List.fromList([0x00, 0x04]));
      expect(block0.sublist(0, 4), [0, 0, 0, 0]);
      expect(block0[4], 0x00); // BCC of an all-zero UID
    });
  });
}
