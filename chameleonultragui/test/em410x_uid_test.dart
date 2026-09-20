import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeEm410xUid', () {
    test('passes through clean 5-byte UID', () {
      final uid = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89]);
      expect(normalizeEm410xUid(uid), uid);
    });

    test('passes through clean 13-byte Electra UID', () {
      final uid = Uint8List.fromList(List<int>.generate(13, (i) => i + 1));
      expect(normalizeEm410xUid(uid, type: TagType.em410XElectra), uid);
    });

    test('strips type prefix from 7-byte scan payload (legacy saved cards)', () {
      // type = EM410X (100 = 0x0064) + 5-byte UID
      final raw = Uint8List.fromList([0x00, 0x64, 0xAB, 0xCD, 0xEF, 0x01, 0x23]);
      expect(
        normalizeEm410xUid(raw),
        Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01, 0x23]),
      );
    });

    test('strips EM410X_64 type prefix (0x0067)', () {
      final raw = Uint8List.fromList([0x00, 0x67, 0x11, 0x22, 0x33, 0x44, 0x55]);
      expect(
        normalizeEm410xUid(raw, type: TagType.em410X64),
        Uint8List.fromList([0x11, 0x22, 0x33, 0x44, 0x55]),
      );
    });

    test('hexToBytes strips colons and spaces', () {
      expect(
        hexToBytes('AB:CD EF-01 23'),
        Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01, 0x23]),
      );
    });

    test('em410xSlotTagType maps variants to base EM410X', () {
      expect(em410xSlotTagType(TagType.em410X), TagType.em410X);
      expect(em410xSlotTagType(TagType.em410X16), TagType.em410X);
      expect(em410xSlotTagType(TagType.em410X32), TagType.em410X);
      expect(em410xSlotTagType(TagType.em410X64), TagType.em410X);
      expect(em410xSlotTagType(TagType.em410XElectra), TagType.em410XElectra);
    });

    test('round-trip: legacy save string load yields 5 bytes', () {
      // Simulates old app saving full scan response as UID hex
      final legacyUidHex = bytesToHexSpace(
          Uint8List.fromList([0x00, 0x64, 0xDE, 0xAD, 0xBE, 0xEF, 0x01]));
      final loaded = normalizeEm410xUid(hexToBytes(legacyUidHex));
      expect(loaded.length, 5);
      expect(loaded, Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x01]));
    });
  });
}
