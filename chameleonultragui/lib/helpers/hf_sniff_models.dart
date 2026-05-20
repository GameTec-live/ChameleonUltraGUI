import 'dart:typed_data';

enum HfSniffDirection { readerToCard, cardToReader }

class HfSniffFrame {
  final int rawBitLength;
  final int bitLength;
  final Uint8List data;
  final HfSniffDirection direction;

  const HfSniffFrame({
    required this.rawBitLength,
    required this.bitLength,
    required this.data,
    required this.direction,
  });

  bool get isReaderToCard => direction == HfSniffDirection.readerToCard;

  bool get isCardToReader => direction == HfSniffDirection.cardToReader;

  String get hexString =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
