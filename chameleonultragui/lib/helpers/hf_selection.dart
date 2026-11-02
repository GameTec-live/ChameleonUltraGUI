import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';

/// Scan responses contain concatenated, variable-length card records.
List<CardData> parseHfScanCards(Uint8List data) {
  final cards = <CardData>[];
  var offset = 0;
  while (offset < data.length) {
    final uidLength = data[offset];
    if (![4, 7, 10].contains(uidLength) ||
        offset + uidLength + 5 > data.length) {
      throw const FormatException('Invalid HF card record');
    }
    final atsLength = data[offset + uidLength + 4];
    final end = offset + uidLength + 5 + atsLength;
    if (end > data.length) {
      throw const FormatException('Truncated HF card record');
    }
    cards.add(
      CardData(
        uid: data.sublist(offset + 1, offset + uidLength + 1),
        atqa: Uint8List.fromList(
          data
              .sublist(offset + uidLength + 1, offset + uidLength + 3)
              .reversed
              .toList(),
        ),
        sak: data[offset + uidLength + 3],
        ats: data.sublist(offset + uidLength + 5, end),
      ),
    );
    offset = end;
  }
  return cards;
}
