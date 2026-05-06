import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class MifareClassicDumpAnalyzer {
  static String hexToAscii(String hex) {
    if (hex.length % 2 != 0) {
      return 'Invalid hex string';
    }

    StringBuffer ascii = StringBuffer();

    for (int i = 0; i < hex.length; i += 2) {
      try {
        int byte = int.parse(hex.substring(i, i + 2), radix: 16);

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

  static List<String> hexBlocksToAscii(List<String> hexBlocks) {
    return hexBlocks.map((block) => hexToAscii(block)).toList();
  }

  static Map<String, dynamic> decodeAccessConditions(
      String accessConditions, BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    if (accessConditions.length != 4) {
      return {
        'error': localizations.invalid_access_conditions_length,
        'readable': false,
      };
    }

    try {
      List<int> bytes = [];
      for (int i = 0; i < 2; i++) {
        bytes.add(
            int.parse(accessConditions.substring(i * 2, i * 2 + 2), radix: 16));
      }

      int c1 = ((bytes[0] >> 4) & 0x0F);
      int c2 = (bytes[1] & 0x0F);
      int c3 = ((bytes[1] >> 4) & 0x0F);

      Map<String, String> blockAccess = {};

      for (int block = 0; block < 3; block++) {
        int bits = ((c1 >> block) & 1) |
            (((c2 >> block) & 1) << 1) |
            (((c3 >> block) & 1) << 2);

        blockAccess['${localizations.block} $block'] =
            _decodeDataBlockAccess(bits, context);
      }

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

  static String _decodeDataBlockAccess(int bits, BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    switch (bits) {
      case 0:
        return '${localizations.read}: A/B, ${localizations.write}: A/B, ${localizations.inc}: A/B, ${localizations.dec}: A/B';
      case 1:
        return '${localizations.read}: A/B, ${localizations.write}: B, ${localizations.inc}: -, ${localizations.dec}: -';
      case 2:
        return '${localizations.read}: A/B, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: -';
      case 3:
        return '${localizations.read}: A/B, ${localizations.write}: B, ${localizations.inc}: B, ${localizations.dec}: A/B';
      case 4:
        return '${localizations.read}: A/B, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: A/B';
      case 5:
        return '${localizations.read}: B, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: -';
      case 6:
        return '${localizations.read}: B, ${localizations.write}: B, ${localizations.inc}: -, ${localizations.dec}: -';
      case 7:
        return '${localizations.read}: -, ${localizations.write}: -, ${localizations.inc}: -, ${localizations.dec}: -';
      default:
        return localizations.unknown;
    }
  }

  static String _decodeSectorTrailerAccess(int bits, BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    switch (bits) {
      case 0:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} A; ${localizations.acl}: ${localizations.read} A, ${localizations.write} -; ${localizations.key} B: ${localizations.read} A, ${localizations.write} A';
      case 1:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} B; ${localizations.acl}: ${localizations.read} A/B, ${localizations.write} -; ${localizations.key} B: ${localizations.read} -, ${localizations.write} B';
      case 2:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.acl}: ${localizations.read} A, ${localizations.write} -; ${localizations.key} B: ${localizations.read} A, ${localizations.write} -';
      case 3:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.acl}: ${localizations.read} A/B, ${localizations.write} -; ${localizations.key} B: ${localizations.read} -, ${localizations.write} -';
      case 4:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} A; ${localizations.acl}: ${localizations.read} A, ${localizations.write} A; ${localizations.key} B: ${localizations.read} A, ${localizations.write} A';
      case 5:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} B; ${localizations.acl}: ${localizations.read} A/B, ${localizations.write} B; ${localizations.key} B: ${localizations.read} -, ${localizations.write} B';
      case 6:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.acl}: ${localizations.read} A/B, ${localizations.write} B; ${localizations.key} B: ${localizations.read} -, ${localizations.write} -';
      case 7:
        return '${localizations.key} A: ${localizations.read} -, ${localizations.write} -; ${localizations.acl}: ${localizations.read} A/B, ${localizations.write} -; ${localizations.key} B: ${localizations.read} -, ${localizations.write} -';
      default:
        return localizations.unknown;
    }
  }

  static int? valueBlockToInt(String valueBlock) {
    if (valueBlock.length != 32) return null;

    try {
      Uint8List bytes = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        bytes[i] = int.parse(valueBlock.substring(i * 2, i * 2 + 2), radix: 16);
      }

      if (!_isValidValueBlock(bytes)) return null;

      int value =
          bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);

      if (value > 0x7FFFFFFF) {
        value = value - 0x100000000;
      }

      return value;
    } catch (e) {
      return null;
    }
  }

  static bool _isValidValueBlock(Uint8List bytes) {
    if (bytes.length != 16) return false;

    for (int i = 0; i < 4; i++) {
      if (bytes[i] != bytes[i + 8]) return false;
    }

    for (int i = 0; i < 4; i++) {
      if (bytes[i + 4] != (0xFF - bytes[i])) return false;
    }

    if (bytes[12] != bytes[14]) return false;
    if (bytes[13] != bytes[15]) return false;
    if (bytes[12] != (0xFF - bytes[13])) return false;

    return true;
  }

  static bool isValidHex(String text) {
    return RegExp(r'^[0-9A-Fa-f-]*$').hasMatch(text);
  }

  static bool isValidBlock(String text) {
    return RegExp(r'^[0-9A-Fa-f-]{32}$').hasMatch(text.trim());
  }

  /// Validate MIFARE Classic access condition bytes (positions 6-8 of sector
  /// trailer). Returns true if the complement bits match the original bits.
  /// Invalid ACL (e.g. all zeros) will brick the sector permanently.
  static bool isValidAcl(Uint8List sectorTrailer) {
    if (sectorTrailer.length < 9) return false;
    final b6 = sectorTrailer[6]; // bits 7-4: ~C2, bits 3-0: ~C1
    final b7 = sectorTrailer[7]; // bits 7-4: C1, bits 3-0: ~C3
    final b8 = sectorTrailer[8]; // bits 7-4: C3, bits 3-0: C2

    // ~C1 must complement C1
    if ((~b6 & 0x0F) != ((b7 >> 4) & 0x0F)) return false;
    // ~C2 must complement C2
    if ((~(b6 >> 4) & 0x0F) != (b8 & 0x0F)) return false;
    // ~C3 must complement C3
    if ((~b7 & 0x0F) != ((b8 >> 4) & 0x0F)) return false;

    return true;
  }

  /// Check whether the sector trailer contains dangerous access conditions
  /// that would permanently lock blocks. Returns a list of locked block
  /// numbers (0-3 within the sector), or empty list if safe.
  ///
  /// Matches Proxmark3's mfReadOnlyAccessConditions logic.
  static List<int> getDangerousAclBlocks(Uint8List sectorTrailer) {
    if (sectorTrailer.length < 9) return [];
    final b7 = sectorTrailer[7]; // C1[7:4] ~C3[3:0]
    final b8 = sectorTrailer[8]; // C3[7:4] C2[3:0]

    // Only consider ACL valid for this check
    if (!isValidAcl(sectorTrailer)) return [];

    final c1 = (b7 >> 4) & 0x0F; // C1_3 C1_2 C1_1 C1_0
    final c2 = b8 & 0x0F; // C2_3 C2_2 C2_1 C2_0
    final c3 = (b8 >> 4) & 0x0F; // C3_3 C3_2 C3_1 C3_0

    final dangerous = <int>[];
    for (int blockn = 0; blockn < 4; blockn++) {
      final c1b = (c1 >> blockn) & 1;
      final c2b = (c2 >> blockn) & 1;
      final c3b = (c3 >> blockn) & 1;
      final cond = (c1b << 2) | (c2b << 1) | c3b;

      if (blockn == 3) {
        // Sector trailer: conditions 2, 6, 7 are dangerous (lock keys/ACL)
        if (cond == 2 || cond == 6 || cond == 7) {
          dangerous.add(blockn);
        }
      } else {
        // Data blocks: conditions 2, 5 are read-only / permanently locked
        if (cond == 2 || cond == 5) {
          dangerous.add(blockn);
        }
      }
    }
    return dangerous;
  }
}
