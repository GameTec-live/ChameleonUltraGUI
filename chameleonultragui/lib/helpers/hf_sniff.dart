import 'dart:typed_data';

enum HfSniffDirection { readerToCard, cardToReader }

class HfSniffFrame {
  final int rawBitLength;
  final int bitLength;
  final Uint8List data;
  final Uint8List parityBits;
  final HfSniffDirection direction;

  const HfSniffFrame({
    required this.rawBitLength,
    required this.bitLength,
    required this.data,
    required this.parityBits,
    required this.direction,
  });

  bool get isReaderToCard => direction == HfSniffDirection.readerToCard;

  bool get isCardToReader => direction == HfSniffDirection.cardToReader;

  String get hexString => _hex(data);

  bool get isShortFrame => data.length == 1 && bitLength > 0 && bitLength < 8;
}

class HfSniffAnnotatedFrame {
  final HfSniffFrame frame;
  final String label;

  const HfSniffAnnotatedFrame({
    required this.frame,
    required this.label,
  });
}

class HfSniffAuthRequest {
  final String keyType;
  final int block;

  const HfSniffAuthRequest({
    required this.keyType,
    required this.block,
  });
}

class HfSniffSummary {
  final int frameCount;
  final int readerFrameCount;
  final int cardFrameCount;
  final String? uid;
  final bool ratsSeen;
  final List<String> aids;
  final List<HfSniffAuthRequest> authRequests;
  final bool arqcSeen;
  final bool tcSeen;
  final bool halted;
  final String? atcLabel;
  final int? amountMinorUnits;

  const HfSniffSummary({
    required this.frameCount,
    required this.readerFrameCount,
    required this.cardFrameCount,
    required this.uid,
    required this.ratsSeen,
    required this.aids,
    required this.authRequests,
    required this.arqcSeen,
    required this.tcSeen,
    required this.halted,
    required this.atcLabel,
    required this.amountMinorUnits,
  });
}

class HfSniffNonceExchange {
  final String uid;
  final int block;
  final String keyType;
  final int nt;
  final int nr;
  final int ar;

  const HfSniffNonceExchange({
    required this.uid,
    required this.block,
    required this.keyType,
    required this.nt,
    required this.nr,
    required this.ar,
  });

  String get ntHex => _u32Hex(nt);

  String get nrHex => _u32Hex(nr);

  String get arHex => _u32Hex(ar);
}

class HfSniffNonceGroup {
  final String uid;
  final int block;
  final String keyType;
  final List<HfSniffNonceExchange> exchanges;

  const HfSniffNonceGroup({
    required this.uid,
    required this.block,
    required this.keyType,
    required this.exchanges,
  });

  bool get canRecover => exchanges.length >= 2;

  String get id => '$uid-$block-$keyType';
}

class HfSniffCapture {
  final Uint8List rawBytes;
  final List<HfSniffFrame> frames;
  final List<HfSniffAnnotatedFrame> annotatedFrames;
  final HfSniffSummary summary;
  final List<HfSniffNonceExchange> nonces;
  final List<HfSniffNonceGroup> nonceGroups;

  const HfSniffCapture({
    required this.rawBytes,
    required this.frames,
    required this.annotatedFrames,
    required this.summary,
    required this.nonces,
    required this.nonceGroups,
  });

  factory HfSniffCapture.fromChameleonBytes(Uint8List chameleonBytes) {
    final frames = parseChameleonHfSniffFrames(chameleonBytes);
    final pm3Bytes = buildProxmarkTrace(frames);
    return HfSniffCapture._build(pm3Bytes, frames);
  }

  factory HfSniffCapture.fromProxmarkTrace(Uint8List traceBytes) {
    final frames = parseProxmarkTrace(traceBytes);
    return HfSniffCapture._build(traceBytes, frames);
  }

  factory HfSniffCapture._build(Uint8List rawBytes, List<HfSniffFrame> frames) {
    final nonces = extractHf14aSniffNonces(frames);
    return HfSniffCapture(
      rawBytes: rawBytes,
      frames: frames,
      annotatedFrames: annotateHf14aSniffFrames(frames),
      summary: summarizeHf14aSniff(frames),
      nonces: nonces,
      nonceGroups: groupHf14aSniffNonces(nonces),
    );
  }
}

List<HfSniffFrame> parseChameleonHfSniffFrames(Uint8List buffer) {
  final frames = <HfSniffFrame>[];
  int offset = 0;

  while (offset + 2 <= buffer.length) {
    final header = (buffer[offset] << 8) | buffer[offset + 1];
    offset += 2;

    final isTx = (header & 0x8000) != 0;
    final rawBitLength = header & 0x7FFF;
    if (rawBitLength == 0) {
      break;
    }

    final rawByteLength = (rawBitLength + 7) ~/ 8;
    if (offset + rawByteLength > buffer.length) {
      break;
    }

    final rawBytes = buffer.sublist(offset, offset + rawByteLength);
    offset += rawByteLength;

    final stripped = _stripParityBits(rawBytes, rawBitLength);
    frames.add(HfSniffFrame(
      rawBitLength: rawBitLength,
      bitLength: stripped.bitLength,
      data: stripped.data,
      parityBits: stripped.parityBits,
      direction:
          isTx ? HfSniffDirection.cardToReader : HfSniffDirection.readerToCard,
    ));
  }

  return frames;
}

Uint8List buildProxmarkTrace(List<HfSniffFrame> frames) {
  final builder = BytesBuilder();
  int timestamp = 0;

  for (final frame in frames) {
    final isResponse = frame.isCardToReader;
    final dataLen = frame.data.length;
    final dataLenField = (dataLen & 0x7FFF) | (isResponse ? 0x8000 : 0);
    final duration = _min((frame.rawBitLength + 1) * 128, 0xFFFF);

    final header = ByteData(8);
    header.setUint32(0, timestamp, Endian.little);
    header.setUint16(4, duration, Endian.little);
    header.setUint16(6, dataLenField, Endian.little);
    builder.add(header.buffer.asUint8List());
    builder.add(frame.data);

    final parityLen = dataLen == 0 ? 1 : ((dataLen - 1) ~/ 8 + 1);
    final parity = Uint8List(parityLen);

    if (frame.isShortFrame) {
      parity[0] = frame.bitLength & 0xFF;
    } else if (frame.parityBits.length == parityLen) {
      parity.setRange(0, parityLen, frame.parityBits);
    } else {
      for (int j = 0; j < dataLen; j++) {
        if (_oddParity8(frame.data[j]) != 0) {
          parity[j >> 3] |= 1 << (7 - (j & 7));
        }
      }
    }

    builder.add(parity);
    timestamp += duration;
  }

  return builder.toBytes();
}

List<HfSniffFrame> parseProxmarkTrace(Uint8List trace) {
  final frames = <HfSniffFrame>[];
  int offset = 0;

  while (offset + 8 <= trace.length) {
    final header = ByteData.sublistView(trace, offset, offset + 8);
    final dataLenField = header.getUint16(6, Endian.little);
    final isResponse = (dataLenField & 0x8000) != 0;
    final dataLen = dataLenField & 0x7FFF;
    final parityLen = dataLen == 0 ? 1 : ((dataLen - 1) ~/ 8 + 1);

    if (offset + 8 + dataLen + parityLen > trace.length) {
      break;
    }

    final data = Uint8List.fromList(
      trace.sublist(offset + 8, offset + 8 + dataLen),
    );
    final parity = Uint8List.fromList(
      trace.sublist(
        offset + 8 + dataLen,
        offset + 8 + dataLen + parityLen,
      ),
    );
    offset += 8 + dataLen + parityLen;

    int bitLength;
    int rawBitLength;
    Uint8List parityBits;

    if (dataLen == 1 && parity.isNotEmpty && parity[0] >= 1 && parity[0] <= 7) {
      bitLength = parity[0];
      rawBitLength = bitLength;
      parityBits = Uint8List(0);
    } else {
      bitLength = dataLen * 8;
      rawBitLength = dataLen * 9;
      parityBits = parity;
    }

    frames.add(HfSniffFrame(
      rawBitLength: rawBitLength,
      bitLength: bitLength,
      data: data,
      parityBits: parityBits,
      direction:
          isResponse ? HfSniffDirection.cardToReader : HfSniffDirection.readerToCard,
    ));
  }

  return frames;
}

List<HfSniffAnnotatedFrame> annotateHf14aSniffFrames(
    List<HfSniffFrame> frames) {
  final annotated = <HfSniffAnnotatedFrame>[];
  bool expectNt = false;
  bool expectNrAr = false;
  String? lastAuthKeyType;
  int? lastAuthBlock;

  for (final frame in frames) {
    final data = frame.data;
    String label;

    if (frame.isReaderToCard &&
        frame.bitLength == 32 &&
        data.length == 4 &&
        data.isNotEmpty &&
        (data[0] == 0x60 || data[0] == 0x61)) {
      lastAuthKeyType = data[0] == 0x60 ? 'A' : 'B';
      lastAuthBlock = data[1];
      expectNt = true;
      expectNrAr = false;
      label =
          'MIFARE Classic AUTH Key$lastAuthKeyType block=0x${lastAuthBlock.toRadixString(16).padLeft(2, '0').toUpperCase()} ($lastAuthBlock)';
    } else if (frame.isCardToReader &&
        expectNt &&
        frame.bitLength == 32 &&
        data.length == 4) {
      label = 'AUTH: NT (card nonce) = ${_hex(data, spaced: false)}';
      expectNt = false;
      expectNrAr = true;
    } else if (frame.isReaderToCard &&
        expectNrAr &&
        frame.bitLength == 64 &&
        data.length == 8) {
      label =
          'AUTH continuation: NR||AR (enc)  NR=${_hex(Uint8List.fromList(data.sublist(0, 4)), spaced: false)}  AR=${_hex(Uint8List.fromList(data.sublist(4, 8)), spaced: false)}';
      expectNrAr = false;
    } else {
      expectNt = false;
      expectNrAr = false;
      label = _decodeHf14aFrame(frame);
    }

    annotated.add(HfSniffAnnotatedFrame(frame: frame, label: label));
  }

  return annotated;
}

HfSniffSummary summarizeHf14aSniff(List<HfSniffFrame> frames) {
  List<int>? uidCl1;
  List<int>? uidCl2;
  List<int>? uidCl3;
  final aids = <String>[];
  final authRequests = <HfSniffAuthRequest>[];
  bool authSeen = false;
  bool arqcSeen = false;
  bool tcSeen = false;
  bool halted = false;
  bool ratsSeen = false;
  String? atcTag;
  int? amountMinorUnits;

  for (final frame in frames) {
    final data = frame.data;
    if (data.isEmpty || frame.isCardToReader) {
      continue;
    }

    final b0 = data[0];
    if ((b0 == 0x93 || b0 == 0x95 || b0 == 0x97) &&
        data.length >= 6 &&
        data[1] == 0x70) {
      final chunk = List<int>.from(data.sublist(2, 6));
      final uidPart =
          (chunk.isNotEmpty && chunk.first == 0x88) ? chunk.sublist(1) : chunk;
      if (b0 == 0x93) {
        uidCl1 = uidPart;
      } else if (b0 == 0x95) {
        uidCl2 = uidPart;
      } else {
        uidCl3 = uidPart;
      }
    }

    if (b0 == 0xE0) {
      ratsSeen = true;
    }

    if (b0 == 0x00 &&
        data.length > 5 &&
        data[1] == 0xA4 &&
        data.length >= 5 + data[4]) {
      final aid = Uint8List.fromList(data.sublist(5, 5 + data[4]));
      final rawAid = _hex(aid, spaced: false).toUpperCase();
      final knownName = _knownAidName(aid);
      final entry = knownName.isEmpty ? rawAid : '$rawAid  ($knownName)';
      if (!aids.contains(entry)) {
        aids.add(entry);
      }
    }

    if ((b0 == 0x60 || b0 == 0x61) && data.length > 1) {
      authSeen = true;
      final keyType = b0 == 0x60 ? 'KeyA' : 'KeyB';
      final block = data[1];
      final exists = authRequests.any(
        (request) => request.keyType == keyType && request.block == block,
      );
      if (!exists) {
        authRequests.add(HfSniffAuthRequest(keyType: keyType, block: block));
      }
    }

    if (b0 == 0x80 && data.length > 2 && data[1] == 0xAE) {
      final mode = data[2] & 0xC0;
      if (mode == 0x80) {
        arqcSeen = true;
      }
      if (mode == 0x40) {
        tcSeen = true;
      }
    }

    if (b0 == 0x80 && data.length > 3 && data[1] == 0xCA) {
      final tag = (data[2] << 8) | data[3];
      atcTag = _knownBerTag(tag) ?? tag.toRadixString(16).padLeft(4, '0');
    }

    if (b0 == 0x80 && data.length >= 11 && data[1] == 0xA8) {
      final amountBytes = data.sublist(5, 11);
      final amount = _bytesToInt(Uint8List.fromList(amountBytes));
      if (amount > 0) {
        amountMinorUnits = amount;
      }
    }

    if (b0 == 0x50 || b0 == 0xC2) {
      halted = true;
    }
  }

  final uidBytes = <int>[
    ...?uidCl1,
    ...?uidCl2,
    ...?uidCl3,
  ];
  final uid = uidBytes.isEmpty ? null : _hex(Uint8List.fromList(uidBytes));

  return HfSniffSummary(
    frameCount: frames.length,
    readerFrameCount: frames.where((frame) => frame.isReaderToCard).length,
    cardFrameCount: frames.where((frame) => frame.isCardToReader).length,
    uid: uid,
    ratsSeen: ratsSeen,
    aids: aids,
    authRequests: authRequests.isEmpty && authSeen
        ? const <HfSniffAuthRequest>[
            HfSniffAuthRequest(keyType: 'unknown', block: -1)
          ]
        : authRequests,
    arqcSeen: arqcSeen,
    tcSeen: tcSeen,
    halted: halted,
    atcLabel: atcTag,
    amountMinorUnits: amountMinorUnits,
  );
}

List<HfSniffNonceExchange> extractHf14aSniffNonces(List<HfSniffFrame> frames) {
  final nonces = <HfSniffNonceExchange>[];
  String uidHex = '00000000';

  for (int index = 0; index < frames.length; index++) {
    final frame = frames[index];
    final data = frame.data;
    if (data.isEmpty) {
      continue;
    }

    if (frame.isReaderToCard &&
        (data[0] == 0x93 || data[0] == 0x95 || data[0] == 0x97) &&
        data.length >= 6 &&
        data[1] == 0x70) {
      final uidPart = List<int>.from(data.sublist(2, 6));
      if (!(data[0] == 0x93 && uidPart.first == 0x88)) {
        uidHex = _hex(Uint8List.fromList(uidPart), spaced: false).toUpperCase();
      }
    }

    if (!frame.isReaderToCard ||
        data.length < 2 ||
        (data[0] != 0x60 && data[0] != 0x61)) {
      continue;
    }

    if (index + 2 >= frames.length) {
      continue;
    }

    final ntFrame = frames[index + 1];
    final nrArFrame = frames[index + 2];
    if (!ntFrame.isCardToReader ||
        ntFrame.data.length != 4 ||
        !nrArFrame.isReaderToCard ||
        nrArFrame.data.length != 8) {
      continue;
    }

    nonces.add(HfSniffNonceExchange(
      uid: uidHex,
      block: data[1],
      keyType: data[0] == 0x60 ? 'A' : 'B',
      nt: _bytesToInt(ntFrame.data),
      nr: _bytesToInt(Uint8List.fromList(nrArFrame.data.sublist(0, 4))),
      ar: _bytesToInt(Uint8List.fromList(nrArFrame.data.sublist(4, 8))),
    ));
  }

  return nonces;
}

List<HfSniffNonceGroup> groupHf14aSniffNonces(
    List<HfSniffNonceExchange> nonces) {
  final grouped = <String, List<HfSniffNonceExchange>>{};

  for (final nonce in nonces) {
    final key = '${nonce.uid}-${nonce.block}-${nonce.keyType}';
    grouped.putIfAbsent(key, () => <HfSniffNonceExchange>[]).add(nonce);
  }

  return grouped.entries.map((entry) {
    final first = entry.value.first;
    return HfSniffNonceGroup(
      uid: first.uid,
      block: first.block,
      keyType: first.keyType,
      exchanges: List<HfSniffNonceExchange>.unmodifiable(entry.value),
    );
  }).toList(growable: false);
}

String buildMfkey64Command(HfSniffNonceGroup group) {
  if (!group.canRecover) {
    final nonce = group.exchanges.first;
    return 'mfkey64 ${group.uid} ${nonce.ntHex} ${nonce.nrHex} ${nonce.arHex} <nt2>';
  }

  final first = group.exchanges[0];
  final second = group.exchanges[1];
  return 'mfkey64 ${group.uid} ${first.ntHex} ${first.nrHex} ${first.arHex} ${second.ntHex}';
}

String buildMfkey32Command(HfSniffNonceGroup group) {
  if (!group.canRecover) {
    return '';
  }

  final first = group.exchanges[0];
  final second = group.exchanges[1];
  return 'mfkey32v2 ${group.uid} ${first.ntHex} ${first.nrHex} ${first.arHex} ${second.ntHex} ${second.nrHex} ${second.arHex}';
}

String buildHfSniffRawHexPreview(Uint8List data, {int maxBytes = 1024}) {
  final rows = <String>[];
  final limit = data.length < maxBytes ? data.length : maxBytes;

  for (int offset = 0; offset < limit; offset += 16) {
    final end = _min(offset + 16, limit);
    final row = Uint8List.fromList(data.sublist(offset, end));
    rows.add(
      '${offset.toRadixString(16).padLeft(4, '0')}  ${_hex(row).padRight(47)}',
    );
  }

  return rows.join('\n');
}

class _StripResult {
  final int bitLength;
  final Uint8List data;
  final Uint8List parityBits;

  const _StripResult(this.bitLength, this.data, this.parityBits);
}

_StripResult _stripParityBits(Uint8List rawBytes, int rawBitLength) {
  if (rawBitLength < 8 || rawBitLength % 9 != 0) {
    return _StripResult(rawBitLength, rawBytes, Uint8List(0));
  }

  final byteCount = rawBitLength ~/ 9;
  final bits = <int>[];
  for (final byte in rawBytes) {
    for (int bit = 0; bit < 8; bit++) {
      bits.add((byte >> bit) & 1);
    }
  }

  final stripped = Uint8List(byteCount);
  final parityPacked = Uint8List((byteCount + 7) >> 3);

  for (int byteIndex = 0; byteIndex < byteCount; byteIndex++) {
    int value = 0;
    for (int bit = 0; bit < 8; bit++) {
      value |= bits[byteIndex * 9 + bit] << bit;
    }
    stripped[byteIndex] = value;

    if (bits[byteIndex * 9 + 8] != 0) {
      parityPacked[byteIndex >> 3] |= 1 << (7 - (byteIndex & 7));
    }
  }

  return _StripResult(byteCount * 8, stripped, parityPacked);
}

int _oddParity8(int byte) {
  int x = byte & 0xFF;
  x ^= x >> 4;
  x ^= x >> 2;
  x ^= x >> 1;
  return (x & 1) ^ 1;
}

String _decodeHf14aFrame(HfSniffFrame frame) {
  final data = frame.data;
  if (data.isEmpty) {
    return '';
  }

  final b0 = data[0];
  final bitLength = frame.bitLength;

  if (bitLength == 16 && data.length == 2) {
    const blocked = <int>{
      0x93,
      0x95,
      0x97,
      0x50,
      0x60,
      0x61,
      0x30,
      0xA0,
      0xA2,
      0xE0
    };
    if (!blocked.contains(data[0])) {
      final atqa = data[0] | (data[1] << 8);
      return 'ATQA (Answer To Request, Type A) = 0x${atqa.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    }
  }

  if (bitLength == 8 && data.length == 1) {
    final sakType = _sakType(data[0]);
    if (sakType != null) {
      return 'SAK (Select Acknowledge) = 0x${data[0].toRadixString(16).padLeft(2, '0').toUpperCase()}  [$sakType]';
    }
    return 'SAK (Select Acknowledge) = 0x${data[0].toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  if (bitLength == 40 && data.length == 5) {
    final calc = data[0] ^ data[1] ^ data[2] ^ data[3];
    final uid = _hex(Uint8List.fromList(data.sublist(0, 4)), spaced: false);
    if (calc == data[4]) {
      return 'ANTICOLL CL1 response: UID=$uid  BCC=0x${data[4].toRadixString(16).padLeft(2, '0').toUpperCase()} (OK)';
    }
    return 'ANTICOLL-like: UID=$uid  BCC=0x${data[4].toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  if (frame.rawBitLength == 7) {
    if (b0 == 0x26) {
      return 'REQA';
    }
    if (b0 == 0x52) {
      return 'WUPA';
    }
    return 'short(0x${b0.toRadixString(16).padLeft(2, '0')})';
  }

  if (b0 == 0x93 || b0 == 0x95 || b0 == 0x97) {
    final level = b0 == 0x93 ? 'CL1' : (b0 == 0x95 ? 'CL2' : 'CL3');
    if (data.length > 1 && data[1] == 0x70) {
      final uid =
          data.length >= 6 ? _hex(Uint8List.fromList(data.sublist(2, 6))) : '';
      return 'SELECT $level  UID=$uid';
    }
    final nvb =
        data.length > 1 ? data[1].toRadixString(16).padLeft(2, '0') : '';
    return 'ANTICOLL $level  NVB=$nvb';
  }

  if (b0 == 0x50) {
    return 'HALT';
  }
  if (b0 == 0xC2) {
    return 'S-DESELECT';
  }
  if (b0 == 0xD0) {
    return data.length > 1
        ? 'PPS  PPS1=${data[1].toRadixString(16).padLeft(2, '0')}'
        : 'PPS';
  }
  if (b0 == 0xE0) {
    final fsdi = data.length > 1 ? (data[1] >> 4) : 0;
    final cid = data.length > 1 ? (data[1] & 0x0F) : 0;
    return 'RATS  FSDI=$fsdi CID=$cid';
  }

  if (b0 == 0x60) {
    return data.length > 1 ? 'AUTH KeyA  block=${data[1]}' : 'AUTH KeyA';
  }
  if (b0 == 0x61) {
    return data.length > 1 ? 'AUTH KeyB  block=${data[1]}' : 'AUTH KeyB';
  }
  if (bitLength == 72) {
    return '(encrypted nonce - auth challenge/response)';
  }
  if (b0 == 0x30) {
    return data.length > 1 ? 'READ  block=${data[1]}' : 'READ';
  }
  if (b0 == 0xA0) {
    return data.length > 1 ? 'WRITE block=${data[1]}' : 'WRITE';
  }
  if (b0 == 0x40) {
    return 'MAGIC WUPC1';
  }
  if (b0 == 0x43) {
    return 'MAGIC WUPC2';
  }
  if (b0 == 0x41) {
    return 'MAGIC WIPE';
  }

  if (data.length >= 2 &&
      (b0 == 0x00 || b0 == 0x80 || b0 == 0x90 || b0 == 0xA0)) {
    final cla = data[0];
    final ins = data[1];
    final p1 = data.length > 2 ? data[2] : 0;
    final p2 = data.length > 3 ? data[3] : 0;

    if (cla == 0x00 && ins == 0xA4) {
      if (data.length > 5 && data.length >= 5 + data[4]) {
        final aid = Uint8List.fromList(data.sublist(5, 5 + data[4]));
        final knownName = _knownAidName(aid);
        final rawAid = _hex(aid).toUpperCase();
        return knownName.isEmpty
            ? 'SELECT AID  $rawAid'
            : 'SELECT AID  $rawAid  ($knownName)';
      }
      return 'SELECT';
    }
    if (cla == 0x00 && ins == 0xB0) {
      final offset = (p1 << 8) | p2;
      final length = data.length > 4 ? data[4] : 0;
      return 'READ BINARY  off=$offset len=$length';
    }
    if (cla == 0x00 && ins == 0xB2) {
      return 'READ RECORD  SFI=${p2 >> 3} rec=$p1';
    }
    if (cla == 0x80 && ins == 0xCA) {
      final tag = (p1 << 8) | p2;
      final name = _knownBerTag(tag);
      return name == null
          ? 'GET DATA  ${p1.toRadixString(16).padLeft(2, '0')}${p2.toRadixString(16).padLeft(2, '0')}'
          : 'GET DATA  ${p1.toRadixString(16).padLeft(2, '0')}${p2.toRadixString(16).padLeft(2, '0')}  ($name)';
    }
    if (cla == 0x80 && ins == 0xA8) {
      return 'GPO  (Get Processing Options)';
    }
    if (cla == 0x80 && ins == 0xAE) {
      final request = switch (p1 & 0xC0) {
        0x00 => 'AAC',
        0x40 => 'TC',
        0x80 => 'ARQC',
        _ => 'AC/${p1.toRadixString(16).padLeft(2, '0')}',
      };
      return 'GENERATE AC  requesting $request';
    }
    if (cla == 0x00 && ins == 0x20) {
      return 'VERIFY PIN';
    }
    if (cla == 0x00 && ins == 0x88) {
      return 'INTERNAL AUTH';
    }
    if (cla == 0x00 && ins == 0x82) {
      return 'EXTERNAL AUTH';
    }
    if (cla == 0x00 && ins == 0x70) {
      return 'MANAGE CHANNEL';
    }
    return 'APDU  CLA=${cla.toRadixString(16).padLeft(2, '0')} INS=${ins.toRadixString(16).padLeft(2, '0')} P1=${p1.toRadixString(16).padLeft(2, '0')} P2=${p2.toRadixString(16).padLeft(2, '0')}';
  }

  for (final swOffset in const <int>[-2, -4]) {
    if (data.length >= swOffset.abs()) {
      final label = _decodeSw(
          data[data.length + swOffset], data[data.length + swOffset + 1]);
      if (label != null) {
        return 'SW ${data[data.length + swOffset].toRadixString(16).padLeft(2, '0').toUpperCase()} ${data[data.length + swOffset + 1].toRadixString(16).padLeft(2, '0').toUpperCase()}  $label';
      }
    }
  }

  return 'unknown (0x${b0.toRadixString(16).padLeft(2, '0')})';
}

String _hex(Uint8List data, {bool spaced = true}) {
  final separator = spaced ? ' ' : '';
  return data
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(separator);
}

int _bytesToInt(Uint8List bytes) {
  int value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
  }
  return value;
}

String _u32Hex(int value) =>
    value.toRadixString(16).padLeft(8, '0').toUpperCase();

String _knownAidName(Uint8List aid) {
  return switch (_hex(aid, spaced: false).toUpperCase()) {
    'A0000000031010' => 'Visa Credit/Debit',
    'A0000000032010' => 'Visa Electron',
    'A0000000033010' => 'Visa Classic',
    'A0000000038010' => 'Visa Plus',
    'A0000000041010' => 'Mastercard',
    'A0000000043060' => 'Maestro',
    'A000000025010801' => 'AmEx',
    'A0000000181002' => 'Mastercard Debit',
    'D2760000850101' => 'NDEF (NFC Forum)',
    'D27600002545' => 'NDEF Type 4',
    '325041592E5359532E4444463031' => 'PPSE (2PAY.SYS.DDF01)',
    _ => '',
  };
}

String? _knownBerTag(int tag) {
  return switch (tag) {
    0x9F36 => 'ATC',
    0x9F13 => 'Last Online ATC',
    0x9F17 => 'PIN Try Counter',
    0x9F4F => 'Log Format',
    0x9F4E => 'Merchant Name',
    _ => null,
  };
}

String? _sakType(int sak) {
  return switch (sak) {
    0x00 => 'MIFARE Ultralight Classic/C/EV1/Nano | NTAG 2xx',
    0x08 => 'MIFARE Classic 1K | Plus SE 1K | Plug S 2K | Plus X 2K',
    0x09 => 'MIFARE Mini 0.3k',
    0x10 => 'MIFARE Plus 2K',
    0x11 => 'MIFARE Plus 4K',
    0x18 => 'MIFARE Classic 4K | Plus S 4K | Plus X 4K',
    0x19 => 'MIFARE Classic 2K',
    0x20 =>
      'MIFARE Plus EV1/EV2 | DESFire EV1/EV2/EV3 | DESFire Light | NTAG 4xx',
    0x28 => 'SmartMX with MIFARE Classic 1K',
    0x38 => 'SmartMX with MIFARE Classic 4K',
    _ => null,
  };
}

String? _decodeSw(int sw1, int sw2) {
  final key = (sw1 << 8) | sw2;
  const exact = <int, String>{
    0x9000: 'OK',
    0x6100: 'Response bytes available',
    0x6283: 'File deactivated',
    0x6300: 'Auth failed',
    0x6400: 'No changes',
    0x6581: 'Memory failure',
    0x6700: 'Wrong length',
    0x6881: 'Logical channel not supported',
    0x6882: 'Secure messaging not supported',
    0x6900: 'Command not allowed',
    0x6981: 'Command incompatible with file structure',
    0x6982: 'Security status not satisfied',
    0x6983: 'Auth method blocked',
    0x6984: 'Referenced data invalidated',
    0x6985: 'Conditions of use not satisfied',
    0x6986: 'Command not allowed - no EF selected',
    0x6A00: 'Wrong parameters P1-P2',
    0x6A80: 'Incorrect data in command',
    0x6A81: 'Function not supported',
    0x6A82: 'File not found',
    0x6A83: 'Record not found',
    0x6A84: 'Not enough memory',
    0x6A85: 'Lc inconsistent with TLV',
    0x6A86: 'Incorrect parameters P1-P2',
    0x6A87: 'Lc inconsistent with P1-P2',
    0x6A88: 'Referenced data not found',
    0x6B00: 'Wrong parameters P1-P2',
    0x6D00: 'Instruction not supported',
    0x6E00: 'Class not supported',
    0x6F00: 'Unknown error',
  };

  if (exact.containsKey(key)) {
    return exact[key];
  }
  if (sw1 == 0x61) {
    return 'Response bytes available: $sw2';
  }
  if (sw1 == 0x62) {
    return 'Warning - no info change: ${sw2.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }
  if (sw1 == 0x63) {
    return 'Warning - state changed: ${sw2.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }
  if (sw1 == 0x6C) {
    return 'Wrong Le - use $sw2';
  }
  if (sw1 == 0x90) {
    return 'OK';
  }
  if (sw1 == 0x91) {
    return 'Proprietary OK';
  }
  return null;
}

int _min(int a, int b) => a < b ? a : b;
