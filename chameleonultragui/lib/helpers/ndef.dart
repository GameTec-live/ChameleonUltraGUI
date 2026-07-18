import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';

enum NdefRecordKind { text, uri, mime, external, raw }

class NdefRecord {
  final int tnf;
  final Uint8List type;
  final Uint8List id;
  final Uint8List payload;

  NdefRecord({
    required this.tnf,
    required List<int> type,
    List<int> id = const [],
    required List<int> payload,
  })  : type = Uint8List.fromList(type),
        id = Uint8List.fromList(id),
        payload = Uint8List.fromList(payload);

  factory NdefRecord.text(String text, {String language = 'en'}) {
    final languageBytes = ascii.encode(language);
    if (languageBytes.length > 63) {
      throw ArgumentError.value(language, 'language');
    }
    return NdefRecord(
      tnf: 1,
      type: ascii.encode('T'),
      payload: [languageBytes.length, ...languageBytes, ...utf8.encode(text)],
    );
  }

  factory NdefRecord.uri(String uri) {
    int prefixIndex = 0;
    for (int i = 1; i < NdefCodec.uriPrefixes.length; i++) {
      if (uri.startsWith(NdefCodec.uriPrefixes[i]) &&
          NdefCodec.uriPrefixes[i].length >
              NdefCodec.uriPrefixes[prefixIndex].length) {
        prefixIndex = i;
      }
    }
    return NdefRecord(
      tnf: 1,
      type: ascii.encode('U'),
      payload: [
        prefixIndex,
        ...utf8
            .encode(uri.substring(NdefCodec.uriPrefixes[prefixIndex].length)),
      ],
    );
  }

  factory NdefRecord.mime(String mimeType, String value) => NdefRecord(
        tnf: 2,
        type: ascii.encode(mimeType),
        payload: utf8.encode(value),
      );

  factory NdefRecord.external(String externalType, String value) => NdefRecord(
        tnf: 4,
        type: ascii.encode(externalType.toLowerCase()),
        payload: utf8.encode(value),
      );

  NdefRecordKind get kind {
    final typeName = ascii.decode(type, allowInvalid: true);
    if (tnf == 1 && typeName == 'T') return NdefRecordKind.text;
    if (tnf == 1 && typeName == 'U') return NdefRecordKind.uri;
    if (tnf == 2) return NdefRecordKind.mime;
    if (tnf == 4) return NdefRecordKind.external;
    return NdefRecordKind.raw;
  }

  String get typeName => ascii.decode(type, allowInvalid: true);

  String get textLanguage {
    if (kind != NdefRecordKind.text || payload.isEmpty) return 'en';
    final languageLength = payload[0] & 0x3F;
    if (payload.length < languageLength + 1) return 'en';
    return ascii.decode(payload.sublist(1, languageLength + 1),
        allowInvalid: true);
  }

  String get displayValue {
    switch (kind) {
      case NdefRecordKind.text:
        if (payload.isEmpty) return '';
        final languageLength = payload[0] & 0x3F;
        if (payload.length < languageLength + 1) return '';
        if (payload[0] & 0x80 != 0) {
          return _decodeUtf16(payload.sublist(languageLength + 1));
        }
        return utf8.decode(payload.sublist(languageLength + 1),
            allowMalformed: true);
      case NdefRecordKind.uri:
        if (payload.isEmpty) return '';
        final prefix = payload[0] < NdefCodec.uriPrefixes.length
            ? NdefCodec.uriPrefixes[payload[0]]
            : '';
        return prefix + utf8.decode(payload.sublist(1), allowMalformed: true);
      case NdefRecordKind.mime:
      case NdefRecordKind.external:
        return utf8.decode(payload, allowMalformed: true);
      case NdefRecordKind.raw:
        return NdefCodec.bytesToHex(payload);
    }
  }

  static String _decodeUtf16(List<int> bytes) {
    if (bytes.length < 2) return '';
    bool littleEndian = bytes[0] == 0xFF && bytes[1] == 0xFE;
    int offset = (bytes[0] == 0xFE && bytes[1] == 0xFF) || littleEndian ? 2 : 0;
    final codeUnits = <int>[];
    while (offset + 1 < bytes.length) {
      codeUnits.add(littleEndian
          ? bytes[offset] | (bytes[offset + 1] << 8)
          : (bytes[offset] << 8) | bytes[offset + 1]);
      offset += 2;
    }
    return String.fromCharCodes(codeUnits);
  }
}

class NdefCodec {
  static const List<String> uriPrefixes = [
    '',
    'http://www.',
    'https://www.',
    'http://',
    'https://',
    'tel:',
    'mailto:',
    'ftp://anonymous:anonymous@',
    'ftp://ftp.',
    'ftps://',
    'sftp://',
    'smb://',
    'nfs://',
    'ftp://',
    'dav://',
    'news:',
    'telnet://',
    'imap:',
    'rtsp://',
    'urn:',
    'pop:',
    'sip:',
    'sips:',
    'tftp:',
    'btspp://',
    'btl2cap://',
    'btgoep://',
    'tcpobex://',
    'irdaobex://',
    'file://',
    'urn:epc:id:',
    'urn:epc:tag:',
    'urn:epc:pat:',
    'urn:epc:raw:',
    'urn:epc:',
    'urn:nfc:',
  ];

  static List<NdefRecord> decodeMessage(List<int> message) {
    if (message.isEmpty) return [];
    final records = <NdefRecord>[];
    int offset = 0;
    bool sawMessageBegin = false;
    bool sawMessageEnd = false;

    while (offset < message.length) {
      final header = message[offset++];
      final messageBegin = header & 0x80 != 0;
      final messageEnd = header & 0x40 != 0;
      final chunked = header & 0x20 != 0;
      final shortRecord = header & 0x10 != 0;
      final hasId = header & 0x08 != 0;
      final tnf = header & 0x07;
      if (chunked) {
        throw const FormatException('Chunked NDEF records unsupported');
      }
      if (records.isEmpty && !messageBegin) {
        throw const FormatException('Missing NDEF message-begin flag');
      }
      if (records.isNotEmpty && messageBegin) {
        throw const FormatException('Unexpected NDEF message-begin flag');
      }
      sawMessageBegin |= messageBegin;

      if (offset >= message.length) {
        throw const FormatException('Truncated NDEF type length');
      }
      final typeLength = message[offset++];
      int payloadLength;
      if (shortRecord) {
        if (offset >= message.length) {
          throw const FormatException('Truncated NDEF payload length');
        }
        payloadLength = message[offset++];
      } else {
        if (offset + 4 > message.length) {
          throw const FormatException('Truncated NDEF payload length');
        }
        payloadLength = (message[offset] << 24) |
            (message[offset + 1] << 16) |
            (message[offset + 2] << 8) |
            message[offset + 3];
        offset += 4;
      }
      int idLength = 0;
      if (hasId) {
        if (offset >= message.length) {
          throw const FormatException('Truncated NDEF ID length');
        }
        idLength = message[offset++];
      }
      final recordEnd = offset + typeLength + idLength + payloadLength;
      if (recordEnd > message.length) {
        throw const FormatException('Truncated NDEF record');
      }
      final type = message.sublist(offset, offset + typeLength);
      offset += typeLength;
      final id = message.sublist(offset, offset + idLength);
      offset += idLength;
      final payload = message.sublist(offset, offset + payloadLength);
      offset += payloadLength;
      records.add(NdefRecord(tnf: tnf, type: type, id: id, payload: payload));

      if (messageEnd) {
        sawMessageEnd = true;
        if (offset != message.length) {
          throw const FormatException('Data follows NDEF message-end record');
        }
        break;
      }
    }
    if (!sawMessageBegin || !sawMessageEnd) {
      throw const FormatException('Incomplete NDEF message');
    }
    return records;
  }

  static Uint8List encodeMessage(List<NdefRecord> records) {
    if (records.isEmpty) return Uint8List(0);
    final output = <int>[];
    for (int index = 0; index < records.length; index++) {
      final record = records[index];
      if (record.type.length > 0xFF || record.id.length > 0xFF) {
        throw const FormatException('NDEF type or ID exceeds 255 bytes');
      }
      final shortRecord = record.payload.length < 256;
      final hasId = record.id.isNotEmpty;
      int header = record.tnf & 0x07;
      if (index == 0) header |= 0x80;
      if (index == records.length - 1) header |= 0x40;
      if (shortRecord) header |= 0x10;
      if (hasId) header |= 0x08;
      output.addAll([header, record.type.length]);
      if (shortRecord) {
        output.add(record.payload.length);
      } else {
        output.addAll([
          (record.payload.length >> 24) & 0xFF,
          (record.payload.length >> 16) & 0xFF,
          (record.payload.length >> 8) & 0xFF,
          record.payload.length & 0xFF,
        ]);
      }
      if (hasId) output.add(record.id.length);
      output.addAll(record.type);
      output.addAll(record.id);
      output.addAll(record.payload);
    }
    return Uint8List.fromList(output);
  }

  static Uint8List hexToBytes(String value) {
    final clean = value.replaceAll(RegExp(r'\s'), '');
    if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
      throw const FormatException('Invalid hexadecimal data');
    }
    return Uint8List.fromList(List<int>.generate(
      clean.length ~/ 2,
      (index) =>
          int.parse(clean.substring(index * 2, index * 2 + 2), radix: 16),
    ));
  }

  static String bytesToHex(List<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

class NdefContainer {
  final String mappingName;
  final List<({int block, int offset})> _locations;
  final Uint8List _region;
  final int _tlvOffset;
  final int _messageOffset;
  final int _messageLength;

  NdefContainer._({
    required this.mappingName,
    required List<({int block, int offset})> locations,
    required List<int> region,
    required int tlvOffset,
    required int messageOffset,
    required int messageLength,
  })  : _locations = locations,
        _region = Uint8List.fromList(region),
        _tlvOffset = tlvOffset,
        _messageOffset = messageOffset,
        _messageLength = messageLength;

  Uint8List get message => Uint8List.fromList(
      _region.sublist(_messageOffset, _messageOffset + _messageLength));

  int get capacity {
    final suffix = _preservedSuffix();
    final available = _region.length - _tlvOffset - 1 - suffix.length;
    final shortCapacity = available > 1 ? (available - 1).clamp(0, 254) : 0;
    final longCapacity = available > 3 ? (available - 3).clamp(0, 0xFFFF) : 0;
    return shortCapacity > longCapacity ? shortCapacity : longCapacity;
  }

  static NdefContainer? detect(TagType tag, List<Uint8List> blocks) {
    if (isMifareUltralight(tag)) return _detectType2(blocks);
    if (isMifareClassic(tag)) return _detectClassic(blocks);
    return null;
  }

  static NdefContainer? _detectType2(List<Uint8List> blocks) {
    if (blocks.length <= 4 || blocks[3].length < 4 || blocks[3][0] != 0xE1) {
      return null;
    }
    final advertisedLength = blocks[3][2] * 8;
    final locations = <({int block, int offset})>[];
    final region = <int>[];
    for (int page = 4;
        page < blocks.length && region.length < advertisedLength;
        page++) {
      for (int offset = 0;
          offset < blocks[page].length && region.length < advertisedLength;
          offset++) {
        locations.add((block: page, offset: offset));
        region.add(blocks[page][offset]);
      }
    }
    return _fromRegion('NFC Forum Type 2', locations, region);
  }

  static NdefContainer? _detectClassic(List<Uint8List> blocks) {
    if (blocks.length < 8 || blocks[1].length != 16 || blocks[2].length != 16) {
      return null;
    }
    final ndefSectors = <int>[];
    final mad1 = [...blocks[1], ...blocks[2]];
    for (int sector = 1; sector <= 15; sector++) {
      final offset = 2 + (sector - 1) * 2;
      if (mad1[offset] == 0x03 && mad1[offset + 1] == 0xE1) {
        ndefSectors.add(sector);
      }
    }
    if (blocks.length >= 128) {
      final mad2 = <int>[];
      for (int block = 64; block <= 66; block++) {
        if (blocks[block].length != 16) return null;
        mad2.addAll(blocks[block]);
      }
      for (int sector = 17; sector <= 39; sector++) {
        final offset = 2 + (sector - 17) * 2;
        if (mad2[offset] == 0x03 && mad2[offset + 1] == 0xE1) {
          ndefSectors.add(sector);
        }
      }
    }
    if (ndefSectors.isEmpty) return null;

    final locations = <({int block, int offset})>[];
    final region = <int>[];
    for (final sector in ndefSectors) {
      final firstBlock = mfClassicGetFirstBlockCountBySector(sector);
      final dataBlockCount = mfClassicGetBlockCountBySector(sector) - 1;
      for (int relativeBlock = 0;
          relativeBlock < dataBlockCount;
          relativeBlock++) {
        final block = firstBlock + relativeBlock;
        if (block >= blocks.length || blocks[block].length != 16) return null;
        for (int offset = 0; offset < 16; offset++) {
          locations.add((block: block, offset: offset));
          region.add(blocks[block][offset]);
        }
      }
    }
    return _fromRegion('MIFARE Classic', locations, region);
  }

  static NdefContainer? _fromRegion(
    String mappingName,
    List<({int block, int offset})> locations,
    List<int> region,
  ) {
    int offset = 0;
    while (offset < region.length) {
      final type = region[offset];
      if (type == 0x00) {
        offset++;
        continue;
      }
      if (type == 0xFE) return null;
      final tlvOffset = offset++;
      if (offset >= region.length) return null;
      int length = region[offset++];
      if (length == 0xFF) {
        if (offset + 2 > region.length) return null;
        length = (region[offset] << 8) | region[offset + 1];
        offset += 2;
      }
      if (offset + length > region.length) return null;
      if (type == 0x03) {
        return NdefContainer._(
          mappingName: mappingName,
          locations: locations,
          region: region,
          tlvOffset: tlvOffset,
          messageOffset: offset,
          messageLength: length,
        );
      }
      offset += length;
    }
    return null;
  }

  List<int> _preservedSuffix() {
    final suffixStart = _messageOffset + _messageLength;
    final terminator = _region.indexOf(0xFE, suffixStart);
    if (terminator < 0) {
      final suffix = _region.sublist(suffixStart);
      return suffix.every((byte) => byte == 0) ? const [] : suffix;
    }
    return _region.sublist(suffixStart, terminator + 1);
  }

  void writeMessage(List<Uint8List> blocks, List<int> newMessage) {
    if (newMessage.length > 0xFFFF) {
      throw RangeError.range(newMessage.length, 0, 0xFFFF, 'newMessage');
    }
    final lengthBytes = newMessage.length < 255
        ? [newMessage.length]
        : [0xFF, (newMessage.length >> 8) & 0xFF, newMessage.length & 0xFF];
    final output = <int>[
      ..._region.sublist(0, _tlvOffset),
      0x03,
      ...lengthBytes,
      ...newMessage,
      ..._preservedSuffix(),
    ];
    if (output.length > _region.length) {
      throw RangeError('NDEF message exceeds the available tag capacity');
    }
    output.addAll(List<int>.filled(_region.length - output.length, 0));
    for (int index = 0; index < _locations.length; index++) {
      final location = _locations[index];
      blocks[location.block][location.offset] = output[index];
    }
  }
}
