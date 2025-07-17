import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class DumpAnalyzer {
  /// Converts hexadecimal string to ASCII representation
  static String hexToAscii(String hex) {
    if (hex.length % 2 != 0) {
      return 'Invalid hex string';
    }

    StringBuffer ascii = StringBuffer();

    for (int i = 0; i < hex.length; i += 2) {
      try {
        int byte = int.parse(hex.substring(i, i + 2), radix: 16);

        // Convert to ASCII character if printable, otherwise use dot
        if (byte >= 32 && byte <= 126) {
          ascii.write(String.fromCharCode(byte));
        } else {
          ascii.write('.');
        }
      } catch (e) {
        ascii.write('?');
      }
    }

    return ascii.toString();
  }

  /// Converts a list of hex blocks to ASCII representation
  static List<String> hexBlocksToAscii(List<String> hexBlocks) {
    return hexBlocks.map((block) => hexToAscii(block)).toList();
  }

  /// Decodes access conditions from the 3-byte access condition field
  static Map<String, dynamic> decodeAccessConditions(
      String accessConditions, BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    if (accessConditions.length != 8) {
      return {
        'error': localizations.invalid_access_conditions_length,
        'readable': false,
      };
    }

    try {
      // Parse the 4 bytes (8 hex characters)
      List<int> bytes = [];
      for (int i = 0; i < 4; i++) {
        bytes.add(
            int.parse(accessConditions.substring(i * 2, i * 2 + 2), radix: 16));
      }

      // Extract C1, C2, C3 bits
      int c1 = ((bytes[1] & 0x80) >> 7) |
          ((bytes[2] & 0x08) >> 2) |
          ((bytes[2] & 0x80) >> 5) |
          ((bytes[0] & 0x08) << 0);

      int c2 = ((bytes[1] & 0x08) >> 3) |
          ((bytes[2] & 0x01) << 1) |
          ((bytes[2] & 0x10) >> 2) |
          ((bytes[0] & 0x01) << 3);

      int c3 = ((bytes[1] & 0x80) >> 4) |
          ((bytes[2] & 0x08) >> 1) |
          ((bytes[2] & 0x80) >> 6) |
          ((bytes[0] & 0x08) >> 1);

      // Decode access conditions for each block
      Map<String, String> blockAccess = {};

      // Data blocks (0-2)
      for (int block = 0; block < 3; block++) {
        int bits = ((c1 >> block) & 1) |
            (((c2 >> block) & 1) << 1) |
            (((c3 >> block) & 1) << 2);

        blockAccess['${localizations.block} $block'] =
            _decodeDataBlockAccess(bits, context);
      }

      // Sector trailer (block 3)
      int trailerBits =
          ((c1 >> 3) & 1) | (((c2 >> 3) & 1) << 1) | (((c3 >> 3) & 1) << 2);

      blockAccess[localizations.sector_trailer] =
          _decodeSectorTrailerAccess(trailerBits, context);

      return {
        'readable': true,
        'c1': c1,
        'c2': c2,
        'c3': c3,
        'access': blockAccess,
      };
    } catch (e) {
      return {
        'error': '${localizations.failed_to_decode_access_conditions}: $e',
        'readable': false,
      };
    }
  }

  /// Decodes data block access conditions
  static String _decodeDataBlockAccess(int bits, BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    switch (bits) {
      case 0:
        return '${localizations.read}: A/B, ${localizations.write}: A/B, ${localizations.inc}: A/B, ${localizations.dec}: A/B';
      case 1:
        return '${localizations.read}: A/B, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: A/B';
      case 2:
        return '${localizations.read}: A/B, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: -';
      case 3:
        return '${localizations.read}: B, ${localizations.write}: B, ${localizations.inc}: -, ${localizations.dec}: -';
      case 4:
        return '${localizations.read}: A/B, ${localizations.write}: B, ${localizations.inc}: -, ${localizations.dec}: -';
      case 5:
        return '${localizations.read}: B, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: -';
      case 6:
        return '${localizations.read}: A/B, ${localizations.write}: B, ${localizations.inc}: B, ${localizations.dec}: A/B';
      case 7:
        return '${localizations.read}: -, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: -';
      default:
        return localizations.unknown;
    }
  }

  /// Decodes sector trailer access conditions
  static String _decodeSectorTrailerAccess(int bits, BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    switch (bits) {
      case 0:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} A; ${localizations.ac}: ${localizations.read} A, ${localizations.write} -; ${localizations.key} B: ${localizations.read} A, ${localizations.write} A';
      case 1:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} A; ${localizations.ac}: ${localizations.read} A, ${localizations.write} A; ${localizations.key} B: ${localizations.read} A, ${localizations.write} A';
      case 2:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.ac}: ${localizations.read} A, ${localizations.write} -; ${localizations.key} B: ${localizations.read} A, ${localizations.write} -';
      case 3:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} B; ${localizations.ac}: ${localizations.read} A/B, ${localizations.write} B; ${localizations.key} B: ${localizations.read} -, ${localizations.write} B';
      case 4:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} B; ${localizations.ac}: ${localizations.read} A/B, ${localizations.write} -; ${localizations.key} B: ${localizations.read} -, ${localizations.write} B';
      case 5:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.ac}: ${localizations.read} A/B, ${localizations.write} B; ${localizations.key} B: ${localizations.read} -, ${localizations.write} -';
      case 6:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.ac}: ${localizations.read} A/B, ${localizations.write} -; ${localizations.key} B: ${localizations.read} -, ${localizations.write} -';
      case 7:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.ac}: ${localizations.read} A/B, ${localizations.write} -; ${localizations.key} B: ${localizations.read} -, ${localizations.write} -';
      default:
        return localizations.unknown;
    }
  }

  /// Converts a value block to its integer representation
  static int? valueBlockToInt(String valueBlock) {
    if (valueBlock.length != 32) return null;

    try {
      // Convert hex string to bytes
      Uint8List bytes = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        bytes[i] = int.parse(valueBlock.substring(i * 2, i * 2 + 2), radix: 16);
      }

      // Verify it's a valid value block
      if (!_isValidValueBlock(bytes)) return null;

      // Extract the value (little-endian, 32-bit signed integer)
      int value =
          bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);

      // Convert from unsigned to signed if necessary
      if (value > 0x7FFFFFFF) {
        value = value - 0x100000000;
      }

      return value;
    } catch (e) {
      return null;
    }
  }

  /// Validates if a block is a proper value block
  static bool _isValidValueBlock(Uint8List bytes) {
    if (bytes.length != 16) return false;

    // Check if bytes 0-3 equal bytes 8-11
    for (int i = 0; i < 4; i++) {
      if (bytes[i] != bytes[i + 8]) return false;
    }

    // Check if bytes 4-7 are inverted bytes 0-3
    for (int i = 0; i < 4; i++) {
      if (bytes[i + 4] != (0xFF - bytes[i])) return false;
    }

    // Check address byte format
    if (bytes[12] != bytes[14]) return false;
    if (bytes[13] != bytes[15]) return false;
    if (bytes[12] != (0xFF - bytes[13])) return false;

    return true;
  }

  /// Validates if a hex string is valid
  static bool isValidHex(String text) {
    return RegExp(r'^[0-9A-Fa-f-]*$').hasMatch(text);
  }

  /// Validates if a block string is valid (32 hex characters)
  static bool isValidBlock(String text) {
    return RegExp(r'^[0-9A-Fa-f-]{32}$').hasMatch(text.trim());
  }
}
