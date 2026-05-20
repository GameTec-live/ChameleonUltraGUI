import 'dart:typed_data';

import 'package:chameleonultragui/helpers/hf_sniff_models.dart';

/// Simple, testable HF (ISO14443-A) passive family inference function.
/// Returns the inferred family name (empty string means unknown/not inferred).
String inferHfCardFamily(List<HfSniffFrame> frames) {
  int? atqa;
  int? sak;
  for (int i = 0; i < frames.length; i++) {
    final frame = frames[i];
    final data = frame.data;
    if (data.isEmpty) continue;

    if (frame.isCardToReader && data.length >= 3) {
      if (i > 0) {
        final prev = frames[i - 1];
        if (prev.isReaderToCard &&
            prev.data.isNotEmpty &&
            prev.data.length == 3 && // 0x60 + 2 byte CRC
            prev.data[0] == 0x60) {
          final hw = data[2];
          if (hw == 0x03) return 'MIFARE Ultralight EV1/Ultralight';
          if (hw == 0x04) return 'NTAG21x';
        }
        if (prev.isReaderToCard &&
            prev.data.isNotEmpty &&
            prev.data[0] == 0x1A) {
          return 'MIFARE Ultralight C';
        }
      }
    }

    if (frame.bitLength == 16 && data.length == 2) {
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
      if (frame.isCardToReader && !blocked.contains(data[0])) {
        atqa = data[0] | (data[1] << 8);
      }
    }
    if (frame.isCardToReader && frame.bitLength == 8 && data.length == 1) {
      sak = data[0];
    }
  }

  if (sak != null) {
    if (sak == 0x08) return 'MIFARE Classic 1K';
    if (sak == 0x18) return 'MIFARE Classic 4K';
    if (sak == 0x09) return 'MIFARE Mini';
    if (sak == 0x00 && atqa == 0x4400) {
      // Ultralight family or NTAG/C: continue searching for subsequent characteristic commands
      for (int i = 0; i < frames.length; i++) {
        final f = frames[i];
        if (f.isReaderToCard &&
            f.data.isNotEmpty &&
            f.data[0] == 0x60 &&
            f.data.length == 3) {
          if (i + 1 < frames.length) {
            final resp = frames[i + 1];
            if (resp.isCardToReader && resp.data.length >= 3) {
              final hw = resp.data[2];
              if (hw == 0x03) return 'MIFARE Ultralight EV1/Ultralight';
              if (hw == 0x04) return 'NTAG21x';
            }
          }
        }
        if (f.isReaderToCard && f.data.isNotEmpty && f.data[0] == 0x1A) {
          return 'MIFARE Ultralight C';
        }
      }
      return 'MIFARE Ultralight (family)';
    }
  }

  return '';
}

enum HfParserState { powerOff, idle, ready, active, halt }

enum PendingUltralightCommand {
  getVersion,
  read,
  fastRead,
  write,
  compatWrite,
  compatWriteData,
  pwdAuth,
  readCnt,
  incrCnt,
  checkTearing,
  readSig,
}

class HfParserContext {
  HfParserState state = HfParserState.powerOff;
  String uid = '';
  final List<int> uidParts = [];
  int? atqa;
  int? sak;
  String family = '';
  bool probableUltralight = false;
  bool probableUltralightEv1 = false;
  PendingUltralightCommand? pendingUlCommand;
  int? pendingPage;
  int? pendingEndPage;
  int? pendingCounter;
  String? pendingAnticollLevel;

  @override
  String toString() =>
      'HfParserContext(state=$state, uid=$uid, family=$family)';
}

class StatefulHfParser {
  final HfParserContext ctx = HfParserContext();
  bool _expectNt = false;
  bool _expectNrAr = false;
  bool _expectAt = false;
  bool _authenticated = false;
  String? _lastAuthKeyType;
  int? _lastAuthBlock;

  void reset() {
    ctx.state = HfParserState.powerOff;
    ctx.uid = '';
    ctx.uidParts.clear();
    ctx.atqa = null;
    ctx.sak = null;
    ctx.family = '';
    _expectNt = false;
    _expectNrAr = false;
    _expectAt = false;
    _authenticated = false;
    _lastAuthKeyType = null;
    _lastAuthBlock = null;
  }

  void feedFrame(HfSniffFrame frame) {
    final data = frame.data;
    if (data.isEmpty) return;

    // detect REQA/WUPA
    if (frame.rawBitLength == 7 &&
        data.length == 1 &&
        (data[0] == 0x26 || data[0] == 0x52)) {
      ctx.state = HfParserState.idle;
      _authenticated = false;
      ctx.uid = '';
      ctx.uidParts.clear();
      ctx.pendingAnticollLevel = null;
      return;
    }

    // ATQA
    if (frame.isCardToReader &&
        frame.bitLength == 16 &&
        data.length == 2 &&
        ctx.state == HfParserState.idle) {
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
      if (blocked.contains(data[0])) {
        return;
      }
      ctx.atqa = data[0] | (data[1] << 8);
      ctx.state = HfParserState.ready;
      return;
    }

    // SAK
    if (frame.isCardToReader && frame.bitLength == 8 && data.length == 1) {
      ctx.sak = data[0];
      if ((data[0] & 0x04) == 0) {
        ctx.uid = _composeUid();
      }
      ctx.family = _inferFamilyFromContext();
      ctx.state = HfParserState.active;
      return;
    }

    // SELECT with UID
    if (data.length >= 6 &&
      (data[0] == 0x93 || data[0] == 0x95 || data[0] == 0x97) &&
      data[1] == 0x70) {
      final level = data[0] == 0x93 ? 'CL1' : (data[0] == 0x95 ? 'CL2' : 'CL3');
      final uidPart =
        (data[2] == 0x88) ? data.sublist(3, 6) : data.sublist(2, 6);
      _storeUidPart(level, uidPart);
      ctx.uid = '';
      // remember anticollision level for next card response
      ctx.pendingAnticollLevel = level;
      ctx.state = HfParserState.ready;
      return;
    }

    // HLTA (50 00 + CRC)
    if (data.length == 4 && data[0] == 0x50 && data[1] == 0x00) {
      ctx.state = HfParserState.halt;
      _authenticated = false;
      return;
    }
  }

  String _inferFamilyFromContext() {
    final atqa = ctx.atqa;
    final sak = ctx.sak;
    if (sak == null) return '';

    if (sak == 0x08) return 'MIFARE Classic 1K';
    if (sak == 0x18) return 'MIFARE Classic 4K';
    if (sak == 0x09) return 'MIFARE Mini';

    if (sak == 0x00 && (atqa == 0x4400 || atqa == 0x0044)) {
      return 'MIFARE Ultralight (family)';
    }

    return '';
  }

  void _storeUidPart(String level, List<int> uidPart) {
    final bytes = List<int>.from(uidPart);
    switch (level) {
      case 'CL1':
        if (ctx.uidParts.isEmpty) {
          ctx.uidParts.addAll(bytes);
        } else {
          ctx.uidParts
            ..clear()
            ..addAll(bytes);
        }
        break;
      case 'CL2':
        if (ctx.uidParts.length <= 3) {
          if (ctx.uidParts.length < 3) {
            ctx.uidParts
              ..clear()
              ..addAll(bytes);
          } else {
            ctx.uidParts.addAll(bytes);
          }
        } else {
          ctx.uidParts
            ..removeRange(3, ctx.uidParts.length)
            ..addAll(bytes);
        }
        break;
      case 'CL3':
        if (ctx.uidParts.length <= 6) {
          if (ctx.uidParts.length < 6) {
            ctx.uidParts
              ..clear()
              ..addAll(bytes);
          } else {
            ctx.uidParts.addAll(bytes);
          }
        } else {
          ctx.uidParts
            ..removeRange(6, ctx.uidParts.length)
            ..addAll(bytes);
        }
        break;
    }
  }

  String _composeUid() {
    if (ctx.uidParts.isEmpty) return '';
    return _hex(Uint8List.fromList(ctx.uidParts));
  }

  String annotateFrame(HfSniffFrame frame) {
    final data = frame.data;
    if (data.isEmpty) return '';

    final isHaltFrame = data.length == 4 && data[0] == 0x50 && data[1] == 0x00;

    // Mifare Classic in authenticated state, treat all frames except HALT as encrypted
    if (_authenticated && !isHaltFrame) {
      final family = ctx.family.isEmpty ? '' : '[${ctx.family}] ';
      return '${family}MIFARE Classic Encrypted (0x${data[0].toRadixString(16).padLeft(2, '0').toLowerCase()})';
    }

    String label = '';

    if (frame.isReaderToCard) {
      // Classic AUTH(1) (0x60 / 0x61) when 4-byte frame
      if (frame.bitLength == 32 &&
          data.length == 4 &&
          (data[0] == 0x60 || data[0] == 0x61)) {
        _lastAuthKeyType = data[0] == 0x60 ? 'A' : 'B';
        _lastAuthBlock = data[1];
        _expectNt = true;
        _expectNrAr = false;
        _expectAt = false;
        label =
            'MIFARE Classic AUTH(1) Key$_lastAuthKeyType block=0x${_lastAuthBlock!.toRadixString(16).padLeft(2, '0').toUpperCase()} ($_lastAuthBlock)';
      }
      // Classic AUTH(2) Reader Response (NR||AR) when a valid 64-bit frame follows AUTH(1)
      else if (_expectNrAr && frame.bitLength == 64 && data.length == 8) {
        label =
            'MIFARE Classic AUTH(2) Reader Response (NR||AR): NR=${_hexBytes(Uint8List.fromList(data.sublist(0, 4)), spaced: false)}  AR=${_hexBytes(Uint8List.fromList(data.sublist(4, 8)), spaced: false)}';
        _expectNrAr = false;
        _expectAt = true;
      } else {
        // Decode other frames
        final decoded = _decodeHf14aFrameWithContext(frame);
        label = decoded.isNotEmpty ? decoded : '';
      }
    } else {
      // card to reader responses
      if (_expectNt && frame.bitLength == 32 && data.length == 4) {
        label =
            'MIFARE Classic AUTH(1) Card Response (NT): NT=${_hexBytes(data, spaced: false)}';
        _expectNt = false;
        _expectNrAr = true;
      }
      // AUTH(2) Card Response (AT) - can be 32-bit (4 bytes) or 28-bit (3-4 bytes)
      else if (_expectAt &&
          (frame.bitLength == 32 || frame.bitLength == 28) &&
          (data.length == 4 || data.length == 3)) {
        label =
            'MIFARE Classic AUTH(2) Card Response (AT): AT=${_hexBytes(data, spaced: false)}';
        _expectAt = false;
        _authenticated = true;
      } else {
        // Decode other frames
        final decoded = _decodeHf14aFrameWithContext(frame);
        label = decoded.isNotEmpty ? decoded : '';
      }
    }

    // prefix with family if known
    final family = ctx.family.isEmpty ? '' : '[${ctx.family}] ';
    return '$family$label';
  }

  String _hexBytes(Uint8List data, {bool spaced = true}) {
    final sep = spaced ? ' ' : '';
    return data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(sep)
        .toUpperCase();
  }

  String _hex(Uint8List data, {bool spaced = true}) =>
      _hexBytes(data, spaced: spaced);

  HfParserContext parseAll(List<HfSniffFrame> frames) {
    reset();
    for (final f in frames) {
      feedFrame(f);
    }
    if (ctx.family.isEmpty) {
      ctx.family = inferHfCardFamily(frames);
    }
    return ctx;
  }

  String _decodeHf14aFrameWithContext(HfSniffFrame frame) {
    final data = frame.data;
    if (data.isEmpty) return _fallbackDecodeHf14aFrame(frame);

    if (frame.isReaderToCard &&
        data.length >= 2 &&
        (data[0] == 0x93 || data[0] == 0x95 || data[0] == 0x97)) {
      ctx.pendingAnticollLevel =
          data[0] == 0x93 ? 'CL1' : (data[0] == 0x95 ? 'CL2' : 'CL3');
    }

    if (frame.isCardToReader && frame.bitLength == 40 && data.length == 5) {
      final level = ctx.pendingAnticollLevel ?? 'CL1';
      final calc = data[0] ^ data[1] ^ data[2] ^ data[3];
      final uid = _hex(Uint8List.fromList(data.sublist(0, 4)), spaced: false);
      if (calc == data[4]) {
        return 'ANTICOLL $level response: UID=$uid  BCC=0x${data[4].toRadixString(16).padLeft(2, '0').toUpperCase()} (OK)';
      }
      return 'ANTICOLL-like $level: UID=$uid  BCC=0x${data[4].toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }

    if (frame.isReaderToCard) {
      final ulLabel = _decodeUltralightReaderCommand(frame);
      if (ulLabel != null) return ulLabel;
    } else {
      final ulLabel = _decodeUltralightCardResponse(frame);
      if (ulLabel != null) return ulLabel;
    }

    return _fallbackDecodeHf14aFrame(frame);
  }

  String? _decodeUltralightReaderCommand(HfSniffFrame frame) {
    final data = frame.data;
    if (data.isEmpty) return null;
    final b0 = data[0];
    if (b0 == 0x60 && (data.length == 1 || data.length == 3)) {
      ctx.probableUltralight = true;
      ctx.probableUltralightEv1 = true;
      ctx.pendingUlCommand = PendingUltralightCommand.getVersion;
      return 'UL EV1 GET_VERSION';
    }
    if (b0 == 0x30 && data.length >= 2) {
      final page = data[1];
      ctx.probableUltralight = true;
      ctx.pendingUlCommand = PendingUltralightCommand.read;
      ctx.pendingPage = page;
      return 'UL READ  page=$page';
    }
    if (b0 == 0x3A && data.length >= 3) {
      final start = data[1];
      final end = data[2];
      ctx.probableUltralight = true;
      ctx.pendingUlCommand = PendingUltralightCommand.fastRead;
      ctx.pendingPage = start;
      ctx.pendingEndPage = end;
      return 'UL FAST_READ start=$start end=$end';
    }
    if (b0 == 0xA2 && data.length >= 6) {
      final page = data[1];
      final payload =
          _hex(Uint8List.fromList(data.sublist(2, 6))).toUpperCase();
      ctx.probableUltralight = true;
      ctx.pendingUlCommand = PendingUltralightCommand.write;
      ctx.pendingPage = page;
      return 'UL WRITE page=$page data=$payload';
    }
    if (b0 == 0xA0 && data.length >= 2) {
      final page = data[1];
      ctx.probableUltralight = true;
      ctx.pendingUlCommand = PendingUltralightCommand.compatWrite;
      ctx.pendingPage = page;
      return 'UL COMPAT_WRITE page=$page';
    }
    if (data.length == 16 &&
        ctx.pendingUlCommand == PendingUltralightCommand.compatWrite) {
      final page = ctx.pendingPage ?? -1;
      ctx.pendingUlCommand = PendingUltralightCommand.compatWriteData;
      return 'UL COMPAT_WRITE DATA page=$page data=${_hex(Uint8List.fromList(data)).toUpperCase()}';
    }
    if (b0 == 0x1B && data.length >= 5) {
      ctx.probableUltralight = true;
      ctx.probableUltralightEv1 = true;
      ctx.pendingUlCommand = PendingUltralightCommand.pwdAuth;
      return 'UL EV1 PWD_AUTH pwd=${_hex(Uint8List.fromList(data.sublist(1, 5))).toUpperCase()}';
    }
    if (b0 == 0x39 && data.length >= 2) {
      ctx.probableUltralight = true;
      ctx.probableUltralightEv1 = true;
      ctx.pendingUlCommand = PendingUltralightCommand.readCnt;
      ctx.pendingCounter = data[1];
      return 'UL EV1 READ_CNT counter=${data[1]}';
    }
    if (b0 == 0xA5 && data.length >= 6) {
      ctx.probableUltralight = true;
      ctx.probableUltralightEv1 = true;
      ctx.pendingUlCommand = PendingUltralightCommand.incrCnt;
      ctx.pendingCounter = data[1];
      final value = _bytesToInt(Uint8List.fromList(data.sublist(2, 5)));
      return 'UL EV1 INCR_CNT counter=${data[1]} inc=$value';
    }
    if (b0 == 0x3E && data.length >= 2) {
      ctx.probableUltralight = true;
      ctx.probableUltralightEv1 = true;
      ctx.pendingUlCommand = PendingUltralightCommand.checkTearing;
      ctx.pendingCounter = data[1];
      return 'UL EV1 CHECK_TEARING_EVENT counter=${data[1]}';
    }
    if (b0 == 0x3C) {
      ctx.probableUltralight = true;
      ctx.probableUltralightEv1 = true;
      ctx.pendingUlCommand = PendingUltralightCommand.readSig;
      return 'UL EV1 READ_SIG';
    }
    return null;
  }

  String? _decodeUltralightCardResponse(HfSniffFrame frame) {
    final data = frame.data;
    if (data.isEmpty) return null;

    if (frame.bitLength == 4 && data.isNotEmpty) {
      final code = data[0] & 0x0F;
      if (code == 0xA) {
        final pending = ctx.pendingUlCommand?.name ?? 'unknown';
        ctx.pendingUlCommand = null;
        return 'UL ACK (for $pending)';
      }
      return 'UL NAK/4bit response code=0x${code.toRadixString(16).toUpperCase()}';
    }

    final pending = ctx.pendingUlCommand;
    if (pending == PendingUltralightCommand.read) {
      final page = ctx.pendingPage ?? -1;
      ctx.pendingUlCommand = null;
      final expected = page >= 0 ? 16 : -1;
      final hasTrailingCrc = data.length == expected + 2;
      final decodeData =
          hasTrailingCrc ? data.sublist(0, data.length - 2) : data;
      final dataHex = _hex(Uint8List.fromList(decodeData)).toUpperCase();
      final crcSuffix = hasTrailingCrc
          ? ' crc=${_hex(Uint8List.fromList(data.sublist(data.length - 2)), spaced: false).toUpperCase()}'
          : '';
      final decoded = _decodeUlReadPages(page, Uint8List.fromList(decodeData));
      if (decodeData.length == 16) {
        final lastPage = page >= 0 ? page + 3 : -1;
        if (lastPage >= 0) {
          return 'UL READ RESP pages=$page-$lastPage len=${data.length} data=$dataHex$crcSuffix decoded=$decoded';
        }
        return 'UL READ RESP len=${data.length} data=$dataHex$crcSuffix decoded=$decoded';
      }
      return 'UL READ RESP? len=${data.length} data=$dataHex$crcSuffix decoded=$decoded';
    }

    if (pending == PendingUltralightCommand.fastRead) {
      final start = ctx.pendingPage ?? -1;
      final end = ctx.pendingEndPage ?? -1;
      ctx.pendingUlCommand = null;
      final expected =
          (start >= 0 && end >= start) ? (end - start + 1) * 4 : -1;
      final hasTrailingCrc = data.length == expected + 2;
      final decodeData =
          hasTrailingCrc ? data.sublist(0, data.length - 2) : data;
      final dataHex = _hex(Uint8List.fromList(decodeData)).toUpperCase();
      final crcSuffix = hasTrailingCrc
          ? ' crc=${_hex(Uint8List.fromList(data.sublist(data.length - 2)), spaced: false).toUpperCase()}'
          : '';
      final decoded = _decodeUlReadPages(start, Uint8List.fromList(decodeData));
      if (start >= 0 && end >= start) {
        return 'UL FAST_READ RESP pages=$start-$end len=${data.length} expected=$expected data=$dataHex$crcSuffix decoded=$decoded';
      }
      return 'UL FAST_READ RESP len=${data.length} data=$dataHex$crcSuffix decoded=$decoded';
    }

    if (pending == PendingUltralightCommand.getVersion) {
      ctx.pendingUlCommand = null;
      if (data.length >= 8) {
        ctx.probableUltralightEv1 = true;
        final versionFamily = data[2] == 0x04
            ? 'NTAG21x'
            : (data[2] == 0x03 ? 'MIFARE Ultralight EV1/Ultralight' : '');
        if (versionFamily.isNotEmpty) {
          ctx.family = versionFamily;
        }
        return 'UL EV1 VERSION vendor=0x${data[0].toRadixString(16).padLeft(2, '0').toUpperCase()} type=0x${data[1].toRadixString(16).padLeft(2, '0').toUpperCase()} sub=0x${data[2].toRadixString(16).padLeft(2, '0').toUpperCase()} ver=${data[3]}.${data[4]} size=0x${data[6].toRadixString(16).padLeft(2, '0').toUpperCase()} proto=0x${data[7].toRadixString(16).padLeft(2, '0').toUpperCase()}';
      }
      return 'UL EV1 VERSION RESP? len=${data.length}';
    }

    if (pending == PendingUltralightCommand.pwdAuth) {
      ctx.pendingUlCommand = null;
      if (data.length >= 2) {
        return 'UL EV1 PWD_AUTH RESP PACK=${_hex(Uint8List.fromList(data.sublist(0, 2))).toUpperCase()}';
      }
      return 'UL EV1 PWD_AUTH RESP? len=${data.length}';
    }

    if (pending == PendingUltralightCommand.readCnt) {
      final counter = ctx.pendingCounter ?? -1;
      ctx.pendingUlCommand = null;
      if (data.length == 5) {
        final counterBytes = Uint8List.fromList(data.sublist(0, 3));
        final value = _bytesToInt(counterBytes);
        final crcSuffix =
            ' crc=${_hex(Uint8List.fromList(data.sublist(3, 5)), spaced: false).toUpperCase()}';
        return 'UL EV1 READ_CNT RESP counter=$counter value=$value$crcSuffix';
      }
      if (data.length == 3) {
        final value = _bytesToInt(Uint8List.fromList(data));
        return 'UL EV1 READ_CNT RESP counter=$counter value=$value';
      }
      return 'UL EV1 READ_CNT RESP? len=${data.length}';
    }

    if (pending == PendingUltralightCommand.checkTearing) {
      final counter = ctx.pendingCounter ?? -1;
      ctx.pendingUlCommand = null;
      if (data.isNotEmpty) {
        return 'UL EV1 CHECK_TEARING_EVENT RESP counter=$counter value=0x${data[0].toRadixString(16).padLeft(2, '0').toUpperCase()}';
      }
      return 'UL EV1 CHECK_TEARING_EVENT RESP? len=${data.length}';
    }

    if (pending == PendingUltralightCommand.readSig) {
      ctx.pendingUlCommand = null;
      if (data.length >= 32) {
        return 'UL EV1 SIGNATURE RESP len=${data.length}';
      }
      return 'UL EV1 SIGNATURE RESP? len=${data.length}';
    }

    if (pending == PendingUltralightCommand.write ||
        pending == PendingUltralightCommand.incrCnt ||
        pending == PendingUltralightCommand.compatWriteData) {
      ctx.pendingUlCommand = null;
      if (data.length == 1 && data[0] == 0x0A) return 'UL ACK';
    }

    return null;
  }

  String _decodeUlReadPages(int startPage, Uint8List data) {
    if (data.isEmpty) return '';

    String? tryAscii(Uint8List pageBytes) {
      if (pageBytes.isEmpty) return null;
      int printable = 0;
      for (final b in pageBytes) {
        if ((b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13) printable++;
      }
      final ratio = printable / pageBytes.length;
      if (ratio >= 0.75) {
        try {
          final s = String.fromCharCodes(pageBytes);
          return s.replaceAll('\r', '\\r').replaceAll('\n', '\\n');
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final pages = <Uint8List>[];
    for (int i = 0; i < data.length; i += 4) {
      pages.add(Uint8List.fromList(
          data.sublist(i, i + 4 > data.length ? data.length : i + 4)));
    }

    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < pages.length; i++) {
      final pnum = (startPage >= 0) ? (startPage + i) : i;
      final pbytes = pages[i];
      final ascii = tryAscii(pbytes);
      final hex = _hex(pbytes).toUpperCase();
      entries.add({'pnum': pnum, 'bytes': pbytes, 'ascii': ascii, 'hex': hex});
    }

    final parts = <String>[];
    int idx = 0;
    while (idx < entries.length) {
      final e = entries[idx];
      final pnum = e['pnum'] as int;
      final pbytes = e['bytes'] as Uint8List;
      final ascii = e['ascii'] as String?;
      final hex = e['hex'] as String;

      if (pnum >= 0 && pnum <= 3) {
        final bcols = pbytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
        String desc;
        if (pnum == 0) {
          desc =
              'UID0-2=${_hex(Uint8List.fromList(pbytes.sublist(0, 3)), spaced: false)} BCC0=0x${pbytes[3].toRadixString(16).padLeft(2, '0').toUpperCase()}';
        } else if (pnum == 1) {
          desc = 'UID3-6=${_hex(pbytes, spaced: false)}';
        } else if (pnum == 2) {
          desc =
              'BCC1=0x${pbytes[0].toRadixString(16).padLeft(2, '0').toUpperCase()} internal=${_hex(Uint8List.fromList(pbytes.sublist(1, 2)))} LOCK0=0x${pbytes[2].toRadixString(16).padLeft(2, '0').toUpperCase()} LOCK1=0x${pbytes[3].toRadixString(16).padLeft(2, '0').toUpperCase()}';
        } else {
          desc = 'OTP0-3=${_hex(pbytes)}';
        }
        parts.add('page $pnum: $bcols ($desc)');
        idx++;
        continue;
      }

      if (pnum >= 4 && ascii != null) {
        final startPage = pnum;
        final asciiParts = [ascii];
        final hexParts = [hex];
        int idx2 = idx + 1;
        while (idx2 < entries.length) {
          final next = entries[idx2];
          final nextPnum = next['pnum'] as int;
          final nextAscii = next['ascii'] as String?;
          final nextHex = next['hex'] as String;
          if (nextPnum == (entries[idx2 - 1]['pnum'] as int) + 1 &&
              nextAscii != null) {
            asciiParts.add(nextAscii);
            hexParts.add(nextHex);
            idx2++;
            continue;
          }
          break;
        }
        final endPage = entries[idx2 - 1]['pnum'] as int;
        final joinedAscii = asciiParts.join();
        if (endPage == startPage) {
          parts.add(
              'page $startPage: user="$joinedAscii" hex=${hexParts.join(' ')}');
        } else {
          parts.add(
              'pages $startPage-$endPage: user="$joinedAscii" hex=${hexParts.join(' ')}');
        }
        idx = idx2;
        continue;
      }

      parts.add('page $pnum: data=$hex');
      idx++;
    }

    return parts.join('; ');
  }

  int _bytesToInt(Uint8List bytes) {
    var value = 0;
    for (final b in bytes) {
      value = (value << 8) | b;
    }
    return value;
  }

  String _fallbackDecodeHf14aFrame(HfSniffFrame frame) {
    final data = frame.data;
    if (data.isEmpty) return '';

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
      if (frame.isCardToReader && !blocked.contains(data[0])) {
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

    // Python: treat 3-byte card->reader SAK+CRC as SAK with (+CRC)
    if (data.length == 3 && frame.isCardToReader && _sakType(data[0]) != null) {
      final sakType = _sakType(data[0]);
      var txt =
          'SAK (Select Acknowledge) = 0x${data[0].toRadixString(16).padLeft(2, '0').toUpperCase()}';
      if (sakType != null) txt += '  [$sakType]';
      txt += '  (+CRC)';
      return txt;
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
      if (b0 == 0x26) return 'REQA';
      if (b0 == 0x52) return 'WUPA';
      return 'short(0x${b0.toRadixString(16).padLeft(2, '0')})';
    }

    if (b0 == 0x93 || b0 == 0x95 || b0 == 0x97) {
      final level = b0 == 0x93 ? 'CL1' : (b0 == 0x95 ? 'CL2' : 'CL3');
      if (data.length > 1 && data[1] == 0x70) {
        final uid = data.length >= 6
            ? _hex(Uint8List.fromList(data.sublist(2, 6)))
            : '';
        return 'SELECT $level  UID=$uid';
      }
      final nvb =
          data.length > 1 ? data[1].toRadixString(16).padLeft(2, '0') : '';
      return 'ANTICOLL $level  NVB=$nvb';
    }

    if (data.length == 4 && b0 == 0x50 && data[1] == 0x00) {
      final crc =
          '${data[2].toRadixString(16).padLeft(2, '0').toUpperCase()}${data[3].toRadixString(16).padLeft(2, '0').toUpperCase()}';
      return 'HALT (50 00 + CRC=$crc)';
    }
    if (b0 == 0x50 && data.length >= 2 && data[1] == 0x00) return 'HALT';
    if (b0 == 0xC2) return 'S-DESELECT';
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
    if (bitLength == 72) return '(encrypted nonce - auth challenge/response)';
    if (b0 == 0x30) return data.length > 1 ? 'READ  block=${data[1]}' : 'READ';
    if (b0 == 0xA0) return data.length > 1 ? 'WRITE block=${data[1]}' : 'WRITE';
    if (b0 == 0x40) return 'MAGIC WUPC1';
    if (b0 == 0x43) return 'MAGIC WUPC2';
    if (b0 == 0x41) return 'MAGIC WIPE';

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
      if (cla == 0x80 && ins == 0xA8) return 'GPO  (Get Processing Options)';
      if (cla == 0x80 && ins == 0xAE) {
        final request = (p1 & 0xC0) == 0x00
            ? 'AAC'
            : (p1 & 0xC0) == 0x40
                ? 'TC'
                : (p1 & 0xC0) == 0x80
                    ? 'ARQC'
                    : 'AC/${p1.toRadixString(16).padLeft(2, '0')}';
        return 'GENERATE AC  requesting $request';
      }
      if (cla == 0x00 && ins == 0x20) return 'VERIFY PIN';
      if (cla == 0x00 && ins == 0x88) return 'INTERNAL AUTH';
      if (cla == 0x00 && ins == 0x82) return 'EXTERNAL AUTH';
      if (cla == 0x00 && ins == 0x70) return 'MANAGE CHANNEL';
      return 'APDU  CLA=${cla.toRadixString(16).padLeft(2, '0')} INS=${ins.toRadixString(16).padLeft(2, '0')} P1=${p1.toRadixString(16).padLeft(2, '0')} P2=${p2.toRadixString(16).padLeft(2, '0')}';
    }

    for (final swOffset in const <int>[-2, -4]) {
      if (data.length >= swOffset.abs()) {
        final sw1 = data[data.length + swOffset];
        final sw2 = data[data.length + swOffset + 1];
        final label = _decodeSw(sw1, sw2);
        if (label != null) {
          return 'SW ${sw1.toRadixString(16).padLeft(2, '0').toUpperCase()} ${sw2.toRadixString(16).padLeft(2, '0').toUpperCase()}  $label';
        }
      }
    }

    // If authenticated (after successful AUTH), mark unknown frames as encrypted
    if (_authenticated) {
      return 'MIFARE Classic Encrypted (0x${b0.toRadixString(16).padLeft(2, '0')})';
    }

    return 'unknown (0x${b0.toRadixString(16).padLeft(2, '0')})';
  }

  String _knownAidName(Uint8List aid) {
    switch (_hex(aid, spaced: false).toUpperCase()) {
      case 'A0000000031010':
        return 'Visa Credit/Debit';
      case 'A0000000032010':
        return 'Visa Electron';
      case 'A0000000033010':
        return 'Visa Classic';
      case 'A0000000038010':
        return 'Visa Plus';
      case 'A0000000041010':
        return 'Mastercard';
      case 'A0000000043060':
        return 'Maestro';
      case 'A000000025010801':
        return 'AmEx';
      case 'A0000000181002':
        return 'Mastercard Debit';
      case 'D2760000850101':
        return 'NDEF (NFC Forum)';
      case 'D27600002545':
        return 'NDEF Type 4';
      case '325041592E5359532E4444463031':
        return 'PPSE (2PAY.SYS.DDF01)';
      default:
        return '';
    }
  }

  String? _knownBerTag(int tag) {
    switch (tag) {
      case 0x9F36:
        return 'ATC';
      case 0x9F13:
        return 'Last Online ATC';
      case 0x9F17:
        return 'PIN Try Counter';
      case 0x9F4F:
        return 'Log Format';
      case 0x9F4E:
        return 'Merchant Name';
      default:
        return null;
    }
  }

  String? _sakType(int sak) {
    switch (sak) {
      case 0x04:
        return 'UID not complete, cascade to next level';
      case 0x00:
        return 'MIFARE Ultralight Classic/C/EV1/Nano | NTAG 2xx';
      case 0x08:
        return 'MIFARE Classic 1K | Plus SE 1K | Plug S 2K | Plus X 2K';
      case 0x09:
        return 'MIFARE Mini 0.3k';
      case 0x10:
        return 'MIFARE Plus 2K';
      case 0x11:
        return 'MIFARE Plus 4K';
      case 0x18:
        return 'MIFARE Classic 4K | Plus S 4K | Plus X 4K';
      case 0x19:
        return 'MIFARE Classic 2K';
      case 0x20:
        return 'MIFARE Plus EV1/EV2 | DESFire EV1/EV2/EV3 | DESFire Light | NTAG 4xx';
      case 0x28:
        return 'SmartMX with MIFARE Classic 1K';
      case 0x38:
        return 'SmartMX with MIFARE Classic 4K';
      default:
        return null;
    }
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
    if (exact.containsKey(key)) return exact[key];
    if (sw1 == 0x61) return 'Response bytes available: $sw2';
    if (sw1 == 0x62) {
      return 'Warning - no info change: ${sw2.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }
    if (sw1 == 0x63) {
      return 'Warning - state changed: ${sw2.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }
    if (sw1 == 0x6C) return 'Wrong Le - use $sw2';
    if (sw1 == 0x90) return 'OK';
    if (sw1 == 0x91) return 'Proprietary OK';
    return null;
  }
}
