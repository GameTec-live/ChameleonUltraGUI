import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/helpers/card_file_import.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';

import 'sl1_profile_test.dart' show fixture;

void main() {
  for (final size in [1024, 4096]) {
    for (final uid in [0x7b, 0x5b]) {
      test(
        'raw $size-byte dump with UID punctuation $uid reaches binary route',
        () {
          for (final whitespacePrefix in [false, true]) {
            final bytes = Uint8List(size);
            bytes.setRange(
              0,
              4,
              whitespacePrefix
                  ? [0x20, 0x09, uid, 0x41]
                  : [uid, 0x41, 0x42, 0x43],
            );
            expect(
              () => importCardText(utf8.decode(bytes), filename: 'card.bin'),
              throwsFormatException,
            );
            // This is the exact catch-route predicate used by the file picker.
            expect(isStructuredCardFile(bytes, filename: 'card.bin'), isFalse);
            expect(
              getTagTypeByDumpSize(bytes.length),
              size == 1024 ? TagType.mifare1K : TagType.mifare4K,
            );
            final printable = Uint8List.fromList(List.filled(size, 0x41));
            printable[0] = uid;
            expect(
              isStructuredCardFile(printable, filename: 'printable.bin'),
              isFalse,
            );
          }
        },
      );
    }
  }
  for (final size in [1024, 4096]) {
    for (final header in [
      '{"name":"Synthetic","id":"archive","uid":"01020304",',
      '{"name":"Synthetic folder","cards":[],"format":"chameleon-ultra-gui-folder",',
      r'{"name":"Synthetic","u\u0069d":"01020304",',
    ]) {
      test(
        'reordered supported object at $size bytes rejects malformed UTF8: $header',
        () {
          final bytes = Uint8List(size)..fillRange(0, size, 32);
          final prefix = utf8.encode(header);
          bytes.setRange(0, prefix.length, prefix);
          bytes[size - 1] = 255;
          expect(() => utf8.decode(bytes), throwsFormatException);
          // saved_cards.dart tests this predicate before getTagTypeByDumpSize.
          var rawFallbackReached = false;
          if (!isStructuredCardFile(bytes, filename: 'reordered.bin')) {
            rawFallbackReached = true;
            getTagTypeByDumpSize(bytes.length);
          }
          expect(rawFallbackReached, isFalse);
        },
      );
    }
  }
  test('declared and recognizable malformed profile text never falls back to binary', () {
    final malformed = Uint8List.fromList(
      utf8.encode('{"format":"chameleon-sl1-profile"'.padRight(1024, ' ')),
    );
    expect(isStructuredCardFile(malformed, filename: 'profile.bin'), isTrue);
    expect(
      () => importCardText(utf8.decode(malformed), filename: 'profile.bin'),
      throwsFormatException,
    );
    final declared = Uint8List(1024)..[0] = 0x7b;
    expect(isStructuredCardFile(declared, filename: 'declared.JSON'), isTrue);
    for (final duplicate in ['"version"', r'"versi\u006fn"']) {
      final source = fixture().export().replaceFirst(
        '"version": 1',
        '"version": 1, $duplicate: 1',
      );
      expect(
        isStructuredCardFile(
          Uint8List.fromList(utf8.encode(source)),
          filename: 'profile.bin',
        ),
        isTrue,
      );
      expect(
        () => importCardText(source, filename: 'profile.bin'),
        throwsFormatException,
      );
    }
  });
  test(
    'one edited block preserves untouched partial coverage and masked trailer',
    () {
      final profile = fixture();
      profile.json['classic']['blocks'][1] = {
        'data': '${'00' * 15}??',
        'status': 'read',
        'key': 'B',
        'errors': [
          {'key': 'A', 'status': 6, 'reason': 'Synthetic A failure'},
        ],
      };
      profile.json['classic']['blocks'][3] = {
        'data': '${'??' * 6}FF078069${'??' * 6}',
        'status': 'read',
        'key': 'A',
        'errors': [
          {'key': 'B', 'status': 6, 'reason': 'Synthetic B failure'},
        ],
      };
      final card = sl1ToCard(profile);
      expect(card.data[1], isEmpty);
      expect(card.data[3], isEmpty);
      final original = Sl1Profile.parse(profile.export());
      card.data[0][0] = 0x11;
      reconcileSl1(card, memoryChanged: true);
      final exported = Sl1Profile.parse(exportSl1Card(card));
      expect(
        exported.json['classic']['blocks'][0]['data'],
        Sl1Profile.encodeBytes(card.data[0]),
      );
      expect(
        exported.json['classic']['blocks'][1],
        original.json['classic']['blocks'][1],
      );
      expect(
        exported.json['classic']['blocks'][3],
        original.json['classic']['blocks'][3],
      );
      expect(
        exported.json['classic']['blocks'][2],
        original.json['classic']['blocks'][2],
      );
      expect(exported.json['classic']['provenance'], 'legacy-unverified');
      expect(exported.json['cardAuth']['enabled'], isFalse);
      expect(() => exported.image(), throwsFormatException);
    },
  );
}
