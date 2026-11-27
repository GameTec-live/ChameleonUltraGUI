import 'classic_coverage.dart';

import 'dart:typed_data';

import 'sl1_profile.dart';

/// Sole owner of the native-card projection contract. No storage/UI dependency:
/// deserialization and device/export boundaries share these exact checks.
class Sl1NativeProjection {
  static const classicTypes = {
    1000: 'mini',
    1001: '1k',
    1002: '2k',
    1003: '4k',
  };
  static String typeForTag(int tag) =>
      classicTypes[tag] ??
      (throw const FormatException('Unsupported Classic geometry'));
  static int tagForType(String type) =>
      classicTypes.entries.firstWhere((e) => e.value == type).key;
  static List<Uint8List> blocks(Sl1Profile profile) =>
      ClassicCoverage.fromClassic(profile.json['classic']).project();
  static Never mismatch(String field) => throw FormatException(
    'Saved card disagrees with its embedded profile ($field). Import a matching standalone profile or correct the native archive; no profile data was discarded.',
  );

  static void validate(
    Sl1Profile profile, {
    required String uid,
    required int sak,
    required List<int> atqa,
    required List<int> ats,
    required int tag,
    required List<List<int>> data,
  }) {
    final p = Sl1Profile.fromJson(profile.json).json;
    final h = p['hf14a'];
    final c = p['classic'];
    if (classicTypes[tag] != c['type']) mismatch('Classic type');
    if (uid.replaceAll(RegExp(r'\s+'), '').toUpperCase() != h['uid']) {
      mismatch('UID');
    }
    if (sak != Sl1Profile.bytes(h['sak']).single) mismatch('SAK');
    if (Sl1Profile.encodeBytes(atqa.reversed) != h['atqa']) mismatch('ATQA');
    if (Sl1Profile.encodeBytes(ats) != (h['ats'] ?? '')) mismatch('ATS');
    final count = Sl1Profile.counts[c['type']]!;
    if (data.length < count ||
        (tag == 1001 && data.length == 72) ||
        data.skip(count).any((b) => b.isNotEmpty)) {
      mismatch('native block geometry');
    }
    final coverage = ClassicCoverage.fromClassic(c);
    for (var block = 0; block < count; block++) {
      if (!coverage.matchesProjection(block, data[block])) {
        mismatch('block $block known/unknown bytes');
      }
    }
  }

  static void validateNativeCoverage(
    ClassicCoverage coverage, {
    required int tag,
    required List<List<int>> data,
  }) {
    if (tag != 1001 || !coverage.isNativeEv1 || data.length != 72) {
      mismatch('native EV1 archival geometry');
    }
    for (var block = 0; block < 72; block++) {
      if (!coverage.matchesProjection(block, data[block])) {
        mismatch('native EV1 block $block known/unknown bytes');
      }
    }
  }
}
