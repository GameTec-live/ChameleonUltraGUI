import 'dart:typed_data';

/// Reader-talk-first scan result shared by EM4x05 and EM4x69 firmware.
class EM4X05Scan {
  final int config;
  final int uid;
  final int uidHigh;
  final bool isEM4X69;
  final int uidBlock;

  EM4X05Scan.fromBytes(Uint8List bytes)
    : config = _word(bytes, 0),
      uid = _word(bytes, 4),
      uidHigh = _word(bytes, 8),
      isEM4X69 = bytes[12] == 1,
      uidBlock = bytes[13];

  static int _word(Uint8List bytes, int offset) {
    if (bytes.length < 14) {
      throw const FormatException('Incomplete EM4x05 scan response');
    }
    return ByteData.sublistView(bytes).getUint32(offset, Endian.big);
  }

  String get tagType => isEM4X69 ? 'EM4x69' : 'EM4x05';
  String get configHex =>
      config.toRadixString(16).padLeft(8, '0').toUpperCase();
  // Format the halves separately to preserve all 64 bits on every platform.
  String get uidHex =>
      '${isEM4X69 ? uidHigh.toRadixString(16).padLeft(8, '0') : ''}'
              '${uid.toRadixString(16).padLeft(8, '0')}'
          .toUpperCase();
  bool get loginUsed => (config & (1 << 6)) != 0;
}
