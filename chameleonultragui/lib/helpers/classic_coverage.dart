import 'dart:convert';
import 'dart:typed_data';

import 'sl1_profile_json.dart';

/// Canonical observations/keys. Native byte arrays are projections, never the
/// source of coverage for untouched blocks. The EV1 envelope is archival only.
class ClassicCoverage {
  static const counts = {'mini': 20, '1k': 64, '2k': 128, '4k': 256};
  static const sectors = {'mini': 5, '1k': 16, '2k': 32, '4k': 40};
  static void validateBlock(dynamic b) {
    requireProfileFields(b, ['data', 'status', 'key', 'errors']);
    requireProfileHex(b['data'], 16, unknown: true);
    if (!['unread', 'read', 'error', 'imported'].contains(b['status']) ||
        ![null, 'A', 'B'].contains(b['key']) ||
        b['errors'] is! List ||
        (['unread', 'error'].contains(b['status']) && b['data'] != '??' * 16)) {
      throw const FormatException('Invalid block coverage');
    }
    for (final e in b['errors']) {
      requireProfileFields(e, ['key', 'status', 'reason']);
      if (!['A', 'B'].contains(e['key']) ||
          (e['status'] != null && e['status'] is! int) ||
          e['reason'] is! String) {
        throw const FormatException('Invalid read error');
      }
    }
  }

  static void validateKeys(dynamic s) {
    requireProfileFields(s, ['a', 'b']);
    for (final k in [s['a'], s['b']]) {
      requireProfileFields(k, ['value', 'status', 'evidence']);
      if (!['unknown', 'provided', 'verified'].contains(k['status']) ||
          (k['evidence'] != null && k['evidence'] is! String) ||
          ((k['status'] == 'unknown') != (k['value'] == null))) {
        throw const FormatException('Invalid key coverage');
      }
      if (k['value'] != null) requireProfileHex(k['value'], 6);
    }
  }

  static const nativeEv1Type = '1k-ev1-native';
  final Map<String, dynamic> json;
  ClassicCoverage._(this.json);
  bool get isNativeEv1 => json['type'] == nativeEv1Type;
  factory ClassicCoverage.fromClassic(dynamic input, {bool nativeEv1 = false}) {
    final p = jsonDecode(jsonEncode(input));
    requireProfileFields(p, ['type', 'provenance', 'blocks', 'keys']);
    final blocks = nativeEv1 ? 72 : ClassicCoverage.counts[p['type']];
    final sectors = nativeEv1 ? 18 : ClassicCoverage.sectors[p['type']];
    if ((nativeEv1 && p['type'] != nativeEv1Type) ||
        blocks == null ||
        ![
          'read',
          'imported',
          'synthetic',
          'legacy-unverified',
        ].contains(p['provenance']) ||
        p['blocks'] is! List ||
        p['blocks'].length != blocks ||
        p['keys'] is! List ||
        p['keys'].length != sectors) {
      throw const FormatException(
        'Invalid canonical Classic coverage geometry/provenance',
      );
    }
    for (final b in p['blocks']) {
      ClassicCoverage.validateBlock(b);
    }
    for (final k in p['keys']) {
      ClassicCoverage.validateKeys(k);
    }
    return ClassicCoverage._(Map<String, dynamic>.from(p));
  }
  factory ClassicCoverage.fromNativeJson(dynamic input) {
    requireProfileFields(input, ['version', 'classic']);
    if (input['version'] is! int || input['version'] != 1) {
      throw const FormatException(
        'Unsupported native Classic coverage version',
      );
    }
    return ClassicCoverage.fromClassic(input['classic'], nativeEv1: true);
  }
  Map<String, dynamic> toNativeJson() {
    if (!isNativeEv1) {
      throw const FormatException(
        'Native coverage envelope is reserved for 72-block EV1 archives',
      );
    }
    return {'version': 1, 'classic': copy().json};
  }

  ClassicCoverage copy() =>
      ClassicCoverage.fromClassic(json, nativeEv1: isNativeEv1);
  int sector(int block) => block < 128 ? block ~/ 4 : 32 + (block - 128) ~/ 16;
  bool isTrailer(int block) {
    final s = sector(block);
    return block == (s < 32 ? s * 4 + 3 : 128 + (s - 32) * 16 + 15);
  }

  Map<int, int> substitutions(int block) {
    final result = <int, int>{};
    if (!isTrailer(block)) return result;
    for (final e in [('a', 0), ('b', 10)]) {
      final key = json['keys'][sector(block)][e.$1]['value'];
      if (key != null) {
        final bytes = decodeProfileHex(key);
        for (var i = 0; i < 6; i++) {
          result[e.$2 + i] = bytes[i];
        }
      }
    }
    return result;
  }

  bool matchesProjection(int block, List<int> native) {
    final observed = json['blocks'][block]['data'] as String;
    if (native.isEmpty) return observed.contains('?');
    if (native.length != 16) return false;
    final keys = substitutions(block);
    for (var i = 0; i < 16; i++) {
      final byte = observed.substring(i * 2, i * 2 + 2);
      if (byte == '??'
          ? keys[i] != native[i]
          : int.parse(byte, radix: 16) != native[i]) {
        return false;
      }
    }
    return true;
  }

  List<Uint8List> project({bool fillKnownKeys = false}) => [
    for (var block = 0; block < json['blocks'].length; block++)
      _projectBlock(block, fillKnownKeys),
  ];
  Uint8List _projectBlock(int block, bool fill) {
    final text = json['blocks'][block]['data'] as String;
    final bytes = List<String>.generate(
      16,
      (i) => text.substring(i * 2, i * 2 + 2),
    );
    if (fill) {
      for (final e in substitutions(block).entries) {
        if (bytes[e.key] == '??') bytes[e.key] = encodeProfileHex([e.value]);
      }
    }
    return bytes.contains('??') ? Uint8List(0) : decodeProfileHex(bytes.join());
  }

  bool reconcile(List<Uint8List> edited) {
    bool changed = false;
    for (
      var block = 0;
      block < json['blocks'].length && block < edited.length;
      block++
    ) {
      if (matchesProjection(block, edited[block])) continue;
      if (edited[block].isNotEmpty && edited[block].length != 16) {
        throw const FormatException(
          'An edited Classic block must contain 16 bytes',
        );
      }
      json['blocks'][block] = {
        'data': edited[block].isEmpty
            ? '??' * 16
            : encodeProfileHex(edited[block]),
        'status': edited[block].isEmpty ? 'unread' : 'imported',
        'key': null,
        'errors': json['blocks'][block]['errors'],
      };
      changed = true;
    }
    if (changed) json['provenance'] = 'legacy-unverified';
    return changed;
  }

  bool patchIdentity({
    required List<int> uid,
    required int sak,
    required List<int> atqa,
    bool vanitySak = false,
  }) {
    if (![4, 7].contains(uid.length) ||
        atqa.length != 2 ||
        sak < 0 ||
        sak > 255) {
      throw const FormatException(
        'Classic identity patch requires a 4/7-byte UID, two ATQA bytes and one SAK byte',
      );
    }
    final old = json['blocks'][0];
    final observed = old['data'] as String;
    final bytes = List.generate(
      16,
      (i) => observed.substring(i * 2, i * 2 + 2),
    );
    final prefix = <int>[
      ...uid,
      if (uid.length == 4) uid.fold<int>(0, (a, b) => a ^ b),
      sak | (vanitySak ? 0x80 : 0),
      ...atqa.reversed,
    ];
    for (var i = 0; i < prefix.length; i++) {
      bytes[i] = encodeProfileHex([prefix[i]]);
    }
    final patched = bytes.join();
    if (patched == observed) return false;
    json['blocks'][0] = {
      'data': patched,
      'status': 'imported',
      'key': null,
      'errors': old['errors'],
    };
    json['provenance'] = 'legacy-unverified';
    return true;
  }

  Uint8List image() {
    if (json['provenance'] == 'legacy-unverified') {
      throw const FormatException(
        'Edited/legacy coverage is unverified; retain the native JSON archive or acquire the card again',
      );
    }
    final image = <int>[];
    for (var block = 0; block < json['blocks'].length; block++) {
      final observed = json['blocks'][block]['data'] as String;
      final bytes = List.generate(
        16,
        (i) => observed.substring(i * 2, i * 2 + 2),
      );
      for (final e in substitutions(block).entries) {
        final value = encodeProfileHex([e.value]);
        if (bytes[e.key] != '??' && bytes[e.key] != value) {
          throw const FormatException('Trailer conflicts with known key');
        }
        bytes[e.key] = value;
      }
      if (bytes.contains('??')) {
        throw FormatException(
          'Block $block has unknown bytes; binary export requires complete canonical coverage',
        );
      }
      final b = decodeProfileHex(bytes.join());
      if (isTrailer(block) &&
          (((b[6] & 15) ^ (b[7] >> 4)) != 15 ||
              ((b[6] >> 4) ^ (b[8] & 15)) != 15 ||
              ((b[7] & 15) ^ (b[8] >> 4)) != 15)) {
        throw FormatException('Invalid access bits in block $block');
      }
      image.addAll(b);
    }
    return Uint8List.fromList(image);
  }
}
