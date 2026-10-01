import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('jablotronCardId converts raw bytes to decimal via BCD', () {
    // Each byte is read as two BCD digits, concatenated across the 5 bytes.
    expect(
      jablotronCardId(Uint8List.fromList([0x00, 0x12, 0x34, 0x56, 0x78])),
      12345678,
    );
    expect(
      jablotronCardId(Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x00])),
      0,
    );
    expect(
      jablotronCardId(Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x01])),
      1,
    );
  });

  test('JablotronCard exposes type, hex string and decimal card number', () {
    final card = JablotronCard.fromUID('0012345678');

    expect(card.type, TagType.jablotron);
    expect(card.toString(), '00 12 34 56 78');
    expect(card.toViewableString(), '12345678 (00 12 34 56 78)');
  });

  test('JablotronCard round-trips through bytes', () {
    final bytes = Uint8List.fromList([0x00, 0x12, 0x34, 0x56, 0x78]);
    final card = JablotronCard.fromBytes(bytes);

    expect(card.uid, bytes);
    expect(card.type, TagType.jablotron);
  });
}
