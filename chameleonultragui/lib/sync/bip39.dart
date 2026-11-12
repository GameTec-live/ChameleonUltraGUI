import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bip39_words.dart';

/// BIP-39 mnemonic encoding of the recovery entropy. The words are only an
/// encoding with a checksum; keys are derived from the raw entropy (see
/// `RecoveryKeys`), not from the BIP-39 PBKDF2 seed.
String entropyToMnemonic(Uint8List entropy) {
  if (entropy.length < 16 || entropy.length > 32 || entropy.length % 4 != 0) {
    throw ArgumentError('Entropy must be 16-32 bytes in steps of 4');
  }
  final bits = StringBuffer();
  for (final byte in entropy) {
    bits.write(byte.toRadixString(2).padLeft(8, '0'));
  }
  final checksum = sha256.convert(entropy).bytes.first;
  bits.write(
    checksum
        .toRadixString(2)
        .padLeft(8, '0')
        .substring(0, entropy.length * 8 ~/ 32),
  );
  final all = bits.toString();
  return [
    for (var i = 0; i < all.length; i += 11)
      bip39English[int.parse(all.substring(i, i + 11), radix: 2)],
  ].join(' ');
}

/// Decodes and checksum-verifies a mnemonic (12-24 words). Throws
/// [FormatException] for unknown words, wrong lengths or bad checksums.
Uint8List mnemonicToEntropy(String mnemonic) {
  final words = mnemonic.trim().toLowerCase().split(RegExp(r'\s+'));
  if (![12, 15, 18, 21, 24].contains(words.length)) {
    throw const FormatException('Wrong number of words');
  }
  final bits = StringBuffer();
  for (final word in words) {
    final index = bip39English.indexOf(word);
    if (index < 0) throw FormatException('Unknown word', word);
    bits.write(index.toRadixString(2).padLeft(11, '0'));
  }
  final all = bits.toString();
  final checksumBits = all.length ~/ 33;
  final entropyBits = all.length - checksumBits;
  final entropy = Uint8List.fromList([
    for (var i = 0; i < entropyBits; i += 8)
      int.parse(all.substring(i, i + 8), radix: 2),
  ]);
  if (entropyToMnemonic(entropy) != words.join(' ')) {
    throw const FormatException('Invalid checksum');
  }
  return entropy;
}
