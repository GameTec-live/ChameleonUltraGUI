import 'dart:typed_data';

/// Gen4 Ultimate/GTU configuration layout and commands, as documented by
/// https://github.com/RfidResearchGroup/proxmark3/blob/master/doc/magic_cards_notes.md#g4top
/// GDM/USCUID cards use a different protocol and are not supported here.
class Gen4Configuration {
  final Uint8List bytes;

  Gen4Configuration(List<int> data) : bytes = Uint8List.fromList(data) {
    if (bytes.length != 30 || bytes[7] > 16) {
      throw const FormatException('Invalid Gen4 configuration');
    }
  }

  factory Gen4Configuration.fromResponse(Uint8List data) {
    // Some cards include two trailing checksum bytes in C6 responses.
    if (data.length != 30 && data.length != 32) {
      throw const FormatException(
        'Expected a 30 or 32 byte Gen4 configuration',
      );
    }
    return Gen4Configuration(data.sublist(0, 30));
  }

  int get protocol => bytes[0];
  int get uidLength => switch (bytes[1]) {
    0 => 4,
    1 => 7,
    2 => 10,
    _ => 0,
  };
  Uint8List get password => bytes.sublist(2, 6);
  int get shadowMode => bytes[6];
  Uint8List get ats => bytes.sublist(8, 8 + bytes[7]);
  // ATQA is stored least significant byte first; display it conventionally.
  Uint8List get atqa => Uint8List.fromList([bytes[25], bytes[24]]);
  int get sak => bytes[26];
  int get ultralightMode => bytes[27];
  int get maxBlock => bytes[28];
  int get block0Mode => bytes[29];
}

typedef Gen4Exchange = Future<Uint8List> Function(Uint8List command);

class Gen4Client {
  final Gen4Exchange exchange;
  Uint8List _password;

  Gen4Client(this.exchange, Uint8List password)
    : _password = Uint8List.fromList(password) {
    if (password.length != 4) throw ArgumentError('Password must be 4 bytes');
  }

  Future<Uint8List> _command(int command, [List<int> data = const []]) =>
      exchange(Uint8List.fromList([0xCF, ..._password, command, ...data]));

  void _checkStatus(Uint8List response) {
    // Gen4 commands return ISO-style 9000, optionally followed by CRC-A.
    if ((response.length != 2 && response.length != 4) ||
        response[0] != 0x90 ||
        response[1] != 0) {
      throw StateError('Gen4 command rejected (${gen4Hex(response)})');
    }
  }

  Future<Gen4Configuration> readConfiguration() async =>
      Gen4Configuration.fromResponse(await _command(0xC6));

  Future<Uint8List> readVersion() => _command(0xCC);

  Future<void> writeConfiguration(
    Gen4Configuration config, {
    bool permanent = false,
  }) async {
    _checkStatus(await _command(permanent ? 0xF1 : 0xF0, config.bytes));
    // FE is rejected on newer cards. F0/F1 changes the password atomically.
    _password = config.password;
  }

  Future<Uint8List> readBlock(int block) async {
    RangeError.checkValueInInterval(block, 0, 255, 'block');
    final data = await _command(0xCE, [block]);
    if (data.length != 16 && data.length != 18) {
      throw const FormatException('Expected a 16 byte block');
    }
    return data.sublist(0, 16);
  }

  Future<void> writeBlock(int block, List<int> data) async {
    RangeError.checkValueInInterval(block, 0, 255, 'block');
    if (data.length != 16) throw ArgumentError('Block must be 16 bytes');
    _checkStatus(await _command(0xCD, [block, ...data]));
  }

  /// Read memory-backed settings in either 16-byte blocks or 4-byte UL pages.
  Future<Uint8List> readMemory(int firstBlock, int length, int stride) async {
    final result = <int>[];
    for (var offset = 0; offset < length; offset += stride) {
      final block = await readBlock(firstBlock + offset ~/ stride);
      result.addAll(
        block.take(length - offset < stride ? length - offset : stride),
      );
    }
    return Uint8List.fromList(result);
  }

  Future<void> writeMemory(int firstBlock, Uint8List data, int stride) async {
    for (var offset = 0; offset < data.length; offset += stride) {
      final address = firstBlock + offset ~/ stride;
      final block = await readBlock(address);
      final count = data.length - offset < stride
          ? data.length - offset
          : stride;
      block.setRange(0, count, data.sublist(offset, offset + count));
      await writeBlock(address, block);
    }
  }

  /// Preserve manufacturer bytes and lock/OTP data when changing the UID.
  Future<void> writeUid(Gen4Configuration config, Uint8List uid) async {
    if (config.uidLength == 0 ||
        config.protocol > 1 ||
        uid.length != config.uidLength) {
      throw ArgumentError('UID must match the configured UID length');
    }
    if (config.protocol == 1 && uid.length == 7) {
      final b0 = await readBlock(0);
      final b1 = await readBlock(1);
      final b2 = await readBlock(2);
      b0.setRange(0, 3, uid);
      b0[3] = 0x88 ^ uid[0] ^ uid[1] ^ uid[2];
      b1.setRange(0, 4, uid.sublist(3));
      b2[0] = uid[3] ^ uid[4] ^ uid[5] ^ uid[6];
      await writeBlock(0, b0);
      await writeBlock(1, b1);
      await writeBlock(2, b2);
    } else {
      final block = await readBlock(0);
      block.setRange(0, uid.length, uid);
      if (config.protocol == 0) {
        block[uid.length] = uid.fold<int>(0, (bcc, byte) => bcc ^ byte);
      }
      await writeBlock(0, block);
    }
  }
}

String gen4Hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

Uint8List gen4ParseHex(String text, {int? length, int? maxLength}) {
  final clean = text.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^(?:[0-9a-fA-F]{2})*$').hasMatch(clean) ||
      (length != null && clean.length != length * 2) ||
      (maxLength != null && clean.length > maxLength * 2)) {
    throw const FormatException('Invalid hexadecimal length or characters');
  }
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
