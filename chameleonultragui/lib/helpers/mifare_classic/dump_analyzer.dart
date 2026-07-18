import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class MifareClassicDumpAnalyzer {
  // Permission masks used by the structured ACL editor:
  // 0 = never, 1 = key A, 2 = key B, 3 = key A or B.
  static const List<List<int>> _dataAccessPermissions = [
    [3, 3, 3, 3],
    [3, 2, 0, 0],
    [3, 0, 0, 0],
    [3, 2, 2, 3],
    [3, 0, 0, 3],
    [2, 0, 0, 0],
    [2, 2, 0, 0],
    [0, 0, 0, 0],
  ];

  // For sector trailers each entry contains Key A, access bits and Key B;
  // every item is [read, write].
  static const List<List<List<int>>> _trailerAccessPermissions = [
    [
      [0, 1],
      [1, 0],
      [1, 1]
    ],
    [
      [0, 2],
      [3, 0],
      [0, 2]
    ],
    [
      [0, 0],
      [1, 0],
      [1, 0]
    ],
    [
      [0, 0],
      [3, 0],
      [0, 0]
    ],
    [
      [0, 1],
      [1, 1],
      [1, 1]
    ],
    [
      [0, 2],
      [3, 2],
      [0, 2]
    ],
    [
      [0, 0],
      [3, 2],
      [0, 0]
    ],
    [
      [0, 0],
      [3, 0],
      [0, 0]
    ],
  ];

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

    if (accessConditions.length != 4 && accessConditions.length != 6) {
      return {
        'error': localizations.invalid_access_conditions_length,
        'readable': false,
      };
    }

    try {
      List<int> bytes = [];
      for (int i = 0; i < accessConditions.length ~/ 2; i++) {
        bytes.add(
            int.parse(accessConditions.substring(i * 2, i * 2 + 2), radix: 16));
      }

      // A four-character value contains bytes 7 and 8 (the legacy caller).
      // A six-character value contains the complete bytes 6, 7 and 8 and can
      // therefore also be checked for inverted-bit redundancy.
      int offset = bytes.length == 3 ? 1 : 0;
      int c1 = ((bytes[offset] >> 4) & 0x0F);
      int c2 = (bytes[offset + 1] & 0x0F);
      int c3 = ((bytes[offset + 1] >> 4) & 0x0F);

      if (bytes.length == 3) {
        int invertedC1 = bytes[0] & 0x0F;
        int invertedC2 = (bytes[0] >> 4) & 0x0F;
        int invertedC3 = bytes[1] & 0x0F;
        if (invertedC1 != ((~c1) & 0x0F) ||
            invertedC2 != ((~c2) & 0x0F) ||
            invertedC3 != ((~c3) & 0x0F)) {
          throw const FormatException('Invalid inverted access bits');
        }
      }

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

  /// Returns the C1/C2/C3 combination (0-7) for data blocks 0-2 and
  /// the sector trailer.
  static List<int>? accessConditionValues(String accessConditions) {
    if (accessConditions.length != 4 && accessConditions.length != 6) {
      return null;
    }

    try {
      int offset = accessConditions.length == 6 ? 2 : 0;
      int byte7 =
          int.parse(accessConditions.substring(offset, offset + 2), radix: 16);
      int byte8 = int.parse(accessConditions.substring(offset + 2, offset + 4),
          radix: 16);
      int c1 = (byte7 >> 4) & 0x0F;
      int c2 = byte8 & 0x0F;
      int c3 = (byte8 >> 4) & 0x0F;

      if (accessConditions.length == 6) {
        int byte6 = int.parse(accessConditions.substring(0, 2), radix: 16);
        if ((byte6 & 0x0F) != ((~c1) & 0x0F) ||
            ((byte6 >> 4) & 0x0F) != ((~c2) & 0x0F) ||
            (byte7 & 0x0F) != ((~c3) & 0x0F)) {
          return null;
        }
      }

      return List<int>.generate(
        4,
        (block) =>
            ((c1 >> block) & 1) |
            (((c2 >> block) & 1) << 1) |
            (((c3 >> block) & 1) << 2),
      );
    } catch (_) {
      return null;
    }
  }

  /// Encodes four C1/C2/C3 combinations into MIFARE Classic bytes 6-8,
  /// including their inverted redundancy bits.
  static String encodeAccessConditions(List<int> values) {
    if (values.length != 4 || values.any((value) => value < 0 || value > 7)) {
      throw ArgumentError.value(values, 'values');
    }

    int c1 = 0;
    int c2 = 0;
    int c3 = 0;
    for (int block = 0; block < 4; block++) {
      c1 |= (values[block] & 1) << block;
      c2 |= ((values[block] >> 1) & 1) << block;
      c3 |= ((values[block] >> 2) & 1) << block;
    }

    int byte6 = (((~c2) & 0x0F) << 4) | ((~c1) & 0x0F);
    int byte7 = (c1 << 4) | ((~c3) & 0x0F);
    int byte8 = (c3 << 4) | c2;
    return [byte6, byte7, byte8]
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  static List<int> dataAccessPermissions(int condition) {
    if (condition < 0 || condition >= _dataAccessPermissions.length) {
      throw RangeError.range(condition, 0, 7, 'condition');
    }
    return List<int>.from(_dataAccessPermissions[condition]);
  }

  static int? dataAccessConditionForPermissions(List<int> permissions) {
    if (permissions.length != 4) return null;
    for (int condition = 0;
        condition < _dataAccessPermissions.length;
        condition++) {
      if (_listEquals(_dataAccessPermissions[condition], permissions)) {
        return condition;
      }
    }
    return null;
  }

  static List<List<int>> trailerAccessPermissions(int condition) {
    if (condition < 0 || condition >= _trailerAccessPermissions.length) {
      throw RangeError.range(condition, 0, 7, 'condition');
    }
    return _trailerAccessPermissions[condition]
        .map((permissions) => List<int>.from(permissions))
        .toList();
  }

  static int? trailerAccessConditionForPermissions(
    List<List<int>> permissions, {
    int? preferredCondition,
  }) {
    bool matches(int condition) =>
        permissions.length == 3 &&
        List<int>.generate(3, (index) => index).every((index) =>
            permissions[index].length == 2 &&
            _listEquals(_trailerAccessPermissions[condition][index],
                permissions[index]));

    if (preferredCondition != null &&
        preferredCondition >= 0 &&
        preferredCondition < _trailerAccessPermissions.length &&
        matches(preferredCondition)) {
      return preferredCondition;
    }
    for (int condition = 0;
        condition < _trailerAccessPermissions.length;
        condition++) {
      if (matches(condition)) return condition;
    }
    return null;
  }

  static bool _listEquals(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (int i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
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

  static int? valueBlockAddress(String valueBlock) {
    if (valueBlock.length != 32) return null;
    try {
      Uint8List bytes = Uint8List.fromList(List<int>.generate(
        16,
        (i) => int.parse(valueBlock.substring(i * 2, i * 2 + 2), radix: 16),
      ));
      return _isValidValueBlock(bytes) ? bytes[12] : null;
    } catch (_) {
      return null;
    }
  }

  /// Creates a complete, redundant MIFARE Classic value block.
  static String intToValueBlock(int value, int address) {
    if (value < -0x80000000 || value > 0x7FFFFFFF) {
      throw RangeError.range(value, -0x80000000, 0x7FFFFFFF, 'value');
    }
    if (address < 0 || address > 0xFF) {
      throw RangeError.range(address, 0, 0xFF, 'address');
    }

    int unsignedValue = value & 0xFFFFFFFF;
    List<int> valueBytes = List<int>.generate(
      4,
      (i) => (unsignedValue >> (i * 8)) & 0xFF,
    );
    List<int> bytes = [
      ...valueBytes,
      ...valueBytes.map((byte) => byte ^ 0xFF),
      ...valueBytes,
      address,
      address ^ 0xFF,
      address,
      address ^ 0xFF,
    ];
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
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
}
