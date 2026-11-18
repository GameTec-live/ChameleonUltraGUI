import 'classic_coverage.dart';
import 'sl1_profile_json.dart';

import 'dart:convert';
import 'dart:typed_data';

/// Lossless interchange metadata. Unknown bytes are never converted to zero.
class Sl1Profile {
  final Map<String, dynamic> json;
  Sl1Profile._(this.json);
  static const counts = ClassicCoverage.counts;
  static const sectors = ClassicCoverage.sectors;
  static void fields(dynamic value, List<String> names) =>
      requireProfileFields(value, names);
  static void hex(dynamic value, int bytes, {bool unknown = false}) =>
      requireProfileHex(value, bytes, unknown: unknown);
  static Uint8List bytes(String value) => decodeProfileHex(value);
  static String encodeBytes(Iterable<int> value) => encodeProfileHex(value);
  static void validateClassicBlock(dynamic value) =>
      ClassicCoverage.validateBlock(value);
  static void validateClassicKeys(dynamic value) =>
      ClassicCoverage.validateKeys(value);
  factory Sl1Profile.parse(String text) =>
      Sl1Profile.fromJson(decodeProfileContainerJson(text));
  factory Sl1Profile.fromJson(dynamic input) {
    final dynamic p = jsonDecode(jsonEncode(input));
    fields(p, ['format', 'version', 'name', 'hf14a', 'classic', 'cardAuth']);
    if (p['format'] != 'chameleon-sl1-profile' ||
        p['version'] is! int ||
        p['version'] != 1 ||
        p['name'] is! String) {
      throw const FormatException('Unsupported profile format/version');
    }
    final h = p['hf14a'];
    fields(h, ['uid', 'atqa', 'sak', 'ats']);
    if (h['uid'] is! String || ![8, 14].contains(h['uid'].length)) {
      throw const FormatException('UID must be 4 or 7 bytes');
    }
    hex(h['uid'], h['uid'].length ~/ 2);
    hex(h['atqa'], 2);
    hex(h['sak'], 1);
    if (h['ats'] != null) {
      if (h['ats'] is! String || h['ats'].length % 2 != 0) {
        throw const FormatException('Invalid ATS');
      }
      hex(h['ats'], h['ats'].length ~/ 2);
      final a = bytes(h['ats']);
      if (a.isNotEmpty &&
          (a.length < 2 || a.length > 254 || a.first != a.length)) {
        throw const FormatException('Invalid ATS length');
      }
    }
    final c = p['classic'];
    fields(c, ['type', 'provenance', 'blocks', 'keys']);
    if (!counts.containsKey(c['type']) ||
        ![
          'read',
          'imported',
          'synthetic',
          'legacy-unverified',
        ].contains(c['provenance']) ||
        c['blocks'] is! List ||
        c['keys'] is! List ||
        c['blocks'].length != counts[c['type']] ||
        c['keys'].length != sectors[c['type']]) {
      throw const FormatException('Invalid Classic geometry/provenance');
    }
    for (final b in c['blocks']) {
      validateClassicBlock(b);
    }
    for (final s in c['keys']) {
      validateClassicKeys(s);
    }
    final a = p['cardAuth'];
    if (a != null) {
      fields(a, ['enabled', 'scenario', 'keyNumber', 'key', 'verification']);
      hex(a['key'], 16);
      fields(a['verification'], ['status', 'evidence']);
      if (a['enabled'] is! bool ||
          a['scenario'] != 'sl1-cardauth-9004' ||
          (a['keyNumber'] is! int || a['keyNumber'] != 36868) ||
          !['provided', 'verified'].contains(a['verification']['status']) ||
          (a['verification']['evidence'] != null &&
              a['verification']['evidence'] is! String)) {
        throw const FormatException('Invalid CardAuth configuration');
      }
      if (a['enabled'] && (h['ats'] == null || h['ats'].length < 4)) {
        throw const FormatException(
          'Enabled CardAuth requires an acquired ATS',
        );
      }
    }
    return Sl1Profile._(Map<String, dynamic>.from(p));
  }
  String export() =>
      const JsonEncoder.withIndent('  ')
          .convert(Sl1Profile.fromJson(json).json);
  List<Uint8List> image() {
    final bytes = ClassicCoverage.fromClassic(json['classic']).image();
    return List.generate(
      bytes.length ~/ 16,
      (i) => bytes.sublist(i * 16, i * 16 + 16),
    );
  }
}
