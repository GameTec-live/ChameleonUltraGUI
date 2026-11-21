import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/ndef.dart';
import 'package:flutter_test/flutter_test.dart';

const _mad1Gpb = 0xC1; // DA, MA, ADV = 1 (MAD1)
const _mad2Gpb = 0xC2; // DA, MA, ADV = 2 (MAD2)
const _uri1k = 'https://example.com/chameleon-ultra/ndef-classic-mad-detection';
const _uri4k =
    'https://example.com/chameleon-ultra/ndef-mad2-sector-15-into-17';
const _shortUri = 'https://example.com/x';

/// Blank card: zero data blocks, transport trailers (GPB 0x69).
List<Uint8List> blankCard(int sectorCount) => [
  for (var sector = 0; sector < sectorCount; sector++) ...[
    for (var i = 1; i < mfClassicGetBlockCountBySector(sector); i++)
      Uint8List(16),
    Uint8List.fromList([
      ...List.filled(6, 0xFF),
      ...[0xFF, 0x07, 0x80, 0x69],
      ...List.filled(6, 0xFF),
    ]),
  ],
];

/// Sets the GPB and lists [sectors] as NDEF (AID E103, stored 03 E1) in the
/// MAD1 (sectors 1-15, blocks 1-2) or MAD2 (sectors 17-39, blocks 64-66).
void writeMad(List<Uint8List> card, int gpb, List<int> sectors) {
  card[3][9] = gpb;
  for (final sector in sectors) {
    final firstBlock = sector < 16 ? 1 : 64;
    final offset = 2 * (sector < 16 ? sector : sector - 16);
    card[firstBlock + offset ~/ 16].setAll(offset % 16, [0x03, 0xE1]);
  }
}

/// Writes an NDEF message TLV and terminator across the data blocks of
/// [sectors].
void writeNdef(List<Uint8List> card, List<int> sectors, String uri) {
  final message = NdefCodec.encodeMessage([NdefRecord.uri(uri)]);
  final tlv = [0x03, message.length, ...message, 0xFE];
  var index = 0;
  for (final sector in sectors) {
    final first = mfClassicGetFirstBlockCountBySector(sector);
    final last = first + mfClassicGetBlockCountBySector(sector) - 1;
    for (var block = first; block < last; block++) {
      for (var offset = 0; offset < 16; offset++, index++) {
        card[block][offset] = index < tlv.length ? tlv[index] : 0;
      }
    }
  }
  expect(index, greaterThanOrEqualTo(tlv.length), reason: 'TLV must fit');
}

/// The shape of a dump read by the app: 256 entries, empty past the card end.
List<Uint8List> padLikeGui(List<Uint8List> card) => [
  ...card,
  ...List.generate(256 - card.length, (_) => Uint8List(0)),
];

List<Uint8List> copy(List<Uint8List> blocks) =>
    blocks.map(Uint8List.fromList).toList();

String? detectedUri(TagType tag, List<Uint8List> blocks) {
  final container = NdefContainer.detect(tag, blocks);
  if (container == null) return null;
  return NdefCodec.decodeMessage(container.message).single.displayValue;
}

/// 1K, MAD1 lists sectors 1 and 2, and the message spans both.
List<Uint8List> ndef1k() {
  final card = blankCard(16);
  writeMad(card, _mad1Gpb, [1, 2]);
  writeNdef(card, [1, 2], _uri1k);
  return card;
}

/// The NDEF area must be sectors 1-2 only: rewriting the message must not
/// touch anything past sector 2.
void expectNdefAreaIsSectors1And2(TagType tag, List<Uint8List> card) {
  final container = NdefContainer.detect(tag, card)!;
  expect(container.capacity, lessThanOrEqualTo(2 * 48 - 3));
  final before = copy(card);
  container.writeMessage(
    card,
    NdefCodec.encodeMessage([NdefRecord.uri(_shortUri)]),
  );
  expect(card.sublist(12), before.sublist(12));
  expect(detectedUri(tag, card), _shortUri);
}

void main() {
  group('NdefContainer.detect on MIFARE Classic', () {
    test('1K padded to 256 entries (as read by the app)', () {
      expect(detectedUri(TagType.mifare1K, padLikeGui(ndef1k())), _uri1k);
    });

    test('4K with a MAD2: message spans sector 15 into 17', () {
      final card = blankCard(40);
      writeMad(card, _mad2Gpb, [15, 17]);
      writeNdef(card, [15, 17], _uri4k);
      final container = NdefContainer.detect(TagType.mifare4K, card)!;
      expect(
        NdefCodec.decodeMessage(container.message).single.displayValue,
        _uri4k,
      );

      final sector16 = copy(card.sublist(64, 68));
      container.writeMessage(
        card,
        NdefCodec.encodeMessage([NdefRecord.uri(_shortUri)]),
      );
      expect(card.sublist(64, 68), sector16);
      expect(detectedUri(TagType.mifare4K, card), _shortUri);
    });

    test('MAD1-only 2K: sector 16 data is not read as a MAD2', () {
      final card = ndef1k()..addAll(blankCard(32).sublist(64));
      card[64].setAll(2, [0x03, 0xE1]); // where a MAD2 would list sector 17
      for (final block in [68, 69, 70]) {
        card[block].fillRange(0, 16, 0xC3);
      }
      expectNdefAreaIsSectors1And2(TagType.mifare2K, padLikeGui(card));
    });

    test('GPB announces a MAD2 that the dump lacks: MAD1 is still used', () {
      final card = ndef1k();
      card[3][9] = _mad2Gpb;
      expect(detectedUri(TagType.mifare1K, card), _uri1k);
      expect(detectedUri(TagType.mifare1K, padLikeGui(card)), _uri1k);
    });
  });
}
