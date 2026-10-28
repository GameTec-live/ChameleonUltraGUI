import 'classic_coverage.dart';
import 'sl1_native_projection.dart';

import 'dart:typed_data';

import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/helpers/definitions.dart';

import 'sl1_profile.dart';

String sl1Type(TagType tag) => Sl1NativeProjection.typeForTag(tag.value);
void validateSl1CardGeometry(CardSave card) {
  final type = sl1Type(card.tag);
  final count = Sl1Profile.counts[type]!;
  if ((card.tag == TagType.mifare1K && card.data.length == 72) ||
      card.data.skip(count).any((block) => block.isNotEmpty)) {
    throw const FormatException(
      'This composite image exceeds common profile v1 geometry. Keep its native card/EV1 export instead.',
    );
  }
}

Sl1Profile legacySl1(CardSave card) {
  validateSl1CardGeometry(card);
  final type = sl1Type(card.tag);
  return Sl1Profile.fromJson({
    'format': 'chameleon-sl1-profile',
    'version': 1,
    'name': card.name,
    'hf14a': {
      'uid': card.uid.replaceAll(' ', '').toUpperCase(),
      'atqa': Sl1Profile.encodeBytes(card.atqa.reversed),
      'sak': Sl1Profile.encodeBytes([card.sak]),
      'ats': card.ats.isEmpty ? null : Sl1Profile.encodeBytes(card.ats),
    },
    'classic': {
      'type': type,
      'provenance': 'legacy-unverified',
      'blocks': List.generate(
        Sl1Profile.counts[type]!,
        (i) => {
          'data': i < card.data.length && card.data[i].length == 16
              ? Sl1Profile.encodeBytes(card.data[i])
              : '??' * 16,
          'status': i < card.data.length && card.data[i].length == 16
              ? 'imported'
              : 'unread',
          'key': null,
          'errors': [],
        },
      ),
      'keys': List.generate(
        Sl1Profile.sectors[type]!,
        (_) => {
          'a': {'value': null, 'status': 'unknown', 'evidence': null},
          'b': {'value': null, 'status': 'unknown', 'evidence': null},
        },
      ),
    },
    'cardAuth': null,
  });
}

CardSave sl1ToCard(Sl1Profile p) => CardSave(
  uid: p.json['hf14a']['uid'],
  name: p.json['name'],
  tag: TagType.values.firstWhere(
    (tag) =>
        tag.value == Sl1NativeProjection.tagForType(p.json['classic']['type']),
  ),
  sak: Sl1Profile.bytes(p.json['hf14a']['sak'])[0],
  atqa: Uint8List.fromList(
    Sl1Profile.bytes(p.json['hf14a']['atqa']).reversed.toList(),
  ),
  ats: Sl1Profile.bytes(p.json['hf14a']['ats'] ?? ''),
  data: Sl1NativeProjection.blocks(p),
  sl1Profile: p,
);

/// Unchanged credentials retain their enabled and verification state.
void updateCardAuthKey(CardSave card, String input) {
  final key = input.trim().toUpperCase();
  if (key.isNotEmpty && !RegExp(r'^[0-9A-F]{32}$').hasMatch(key)) {
    throw const FormatException('Enter exactly 32 hex characters');
  }
  final previous = card.sl1Profile?.json['cardAuth'];
  if (key == (previous?['key'] ?? '')) return;
  final profile = Sl1Profile.parse(
    (card.sl1Profile ?? legacySl1(card)).export(),
  );
  if (card.sl1Profile == null) {
    // A complete legacy image is supplied data, not read-verified coverage.
    // Validate it before attaching a profile or replacing the native archive.
    profile.json['classic']['provenance'] = 'imported';
    profile.image();
  }
  profile.json['cardAuth'] = key.isEmpty
      ? null
      : {
          'enabled': true,
          'scenario': 'sl1-cardauth-9004',
          'keyNumber': 0x9004,
          'key': key,
          'verification': {'status': 'provided', 'evidence': null},
        };
  final validated = Sl1Profile.fromJson(profile.json);
  card.sl1Profile = validated;
  card.data = Sl1NativeProjection.blocks(validated);
}

/// Identity edits preserve coverage; memory edits retain bytes but require a
/// fresh explicit coverage import before profile upload.
void reconcileSl1(CardSave card, {bool memoryChanged = false}) {
  if (card.sl1Profile == null) return;
  if (![
    TagType.mifareMini,
    TagType.mifare1K,
    TagType.mifare2K,
    TagType.mifare4K,
  ].contains(card.tag)) {
    throw const FormatException(
      'Remove the Classic/CardAuth profile before changing to a non-Classic type',
    );
  }
  final p = Sl1Profile.parse(card.sl1Profile!.export()).json;
  if (sl1Type(card.tag) != p['classic']['type']) {
    throw const FormatException(
      'Classic geometry cannot change while a canonical profile is attached. Retain/export the original profile before creating a separate card of another type.',
    );
  }
  p['name'] = card.name;
  final h = p['hf14a'];
  final oldIdentity = h.toString();
  h['uid'] = card.uid.replaceAll(' ', '').toUpperCase();
  h['atqa'] = Sl1Profile.encodeBytes(card.atqa.reversed);
  h['sak'] = Sl1Profile.encodeBytes([card.sak]);
  h['ats'] = card.ats.isEmpty
      ? (h['ats'] == null ? null : '')
      : Sl1Profile.encodeBytes(card.ats);
  if (memoryChanged) {
    final coverage = ClassicCoverage.fromClassic(p['classic']);
    memoryChanged = coverage.reconcile(card.data);
    p['classic'] = coverage.json;
  }
  if (oldIdentity != h.toString()) {
    for (final sector in p['classic']['keys']) {
      for (final name in ['a', 'b']) {
        if (sector[name]['value'] != null) {
          sector[name]['status'] = 'provided';
          sector[name]['evidence'] = null;
        }
      }
    }
  }
  if (p['cardAuth'] != null && (oldIdentity != h.toString() || memoryChanged)) {
    p['cardAuth']['verification'] = {'status': 'provided', 'evidence': null};
    p['cardAuth']['enabled'] = false;
  }
  card.sl1Profile = Sl1Profile.fromJson(p);
}

/// Apply only the approved identity positions to canonical observations. The
/// legacy projection remains empty whenever any unrelated byte is unknown.
void patchSl1BlockZeroIdentity(
  CardSave card, {
  required Sl1Profile source,
  bool vanitySak = false,
}) {
  if (card.sl1Profile == null) {
    throw const FormatException('Card has no profile');
  }
  final coverage = ClassicCoverage.fromClassic(source.json['classic']);
  final changed = coverage.patchIdentity(
    uid: Sl1Profile.bytes(card.uid.replaceAll(' ', '').toUpperCase()),
    sak: card.sak,
    atqa: card.atqa,
    vanitySak: vanitySak,
  );
  final patched = coverage.json['blocks'][0]['data'] as String;
  final p = Sl1Profile.parse(card.sl1Profile!.export()).json;
  p['classic']['blocks'][0] = coverage.json['blocks'][0];
  if (changed) {
    p['classic']['provenance'] = 'legacy-unverified';
    for (final sector in p['classic']['keys']) {
      for (final name in ['a', 'b']) {
        if (sector[name]['value'] != null) {
          sector[name]['status'] = 'provided';
          sector[name]['evidence'] = null;
        }
      }
    }
    if (p['cardAuth'] != null) {
      p['cardAuth']['enabled'] = false;
      p['cardAuth']['verification'] = {'status': 'provided', 'evidence': null};
    }
  }
  final validated = Sl1Profile.fromJson(p);
  final projection = List<Uint8List>.from(card.data);
  if (projection.isEmpty) projection.add(Uint8List(0));
  projection[0] = patched.contains('?')
      ? Uint8List(0)
      : Sl1Profile.bytes(patched);
  card.sl1Profile = validated;
  card.data = projection;
}

/// Native EV1 metadata is archival; edits retain observations and key history.
void reconcileNativeClassicCoverage(
  CardSave card, {
  required CardSave previous,
  bool patchBlockZero = false,
  bool vanitySak = false,
}) {
  if (card.nativeClassicCoverage == null) return;
  if (card.tag != TagType.mifare1K) {
    throw const FormatException(
      'Native EV1 coverage is archival metadata for the original 1K EV1 geometry; retain/export that archive before changing type',
    );
  }
  final coverage = card.nativeClassicCoverage!.copy();
  coverage.reconcile(card.data);
  if (patchBlockZero) {
    coverage.patchIdentity(
      uid: Sl1Profile.bytes(card.uid.replaceAll(' ', '').toUpperCase()),
      sak: card.sak,
      atqa: card.atqa,
      vanitySak: vanitySak,
    );
  }
  final identityChanged =
      card.uid.replaceAll(' ', '').toUpperCase() !=
          previous.uid.replaceAll(' ', '').toUpperCase() ||
      card.sak != previous.sak ||
      !classicBlockListsEqual(
        [card.atqa, card.ats],
        [previous.atqa, previous.ats],
      );
  if (identityChanged) coverage.json['provenance'] = 'legacy-unverified';
  card.nativeClassicCoverage = coverage;
  card.data = coverage.project(fillKnownKeys: true);
  card.validateProfileConsistency();
}

String exportSl1Card(CardSave card) {
  card.validateProfileConsistency();
  validateSl1CardGeometry(card);
  if (card.sl1Profile == null) {
    throw const FormatException('Card has no profile');
  }
  final p = Sl1Profile.parse(card.sl1Profile!.export()).json;
  p['name'] = card.name;
  return Sl1Profile.fromJson(p).export();
}

/// Compare projections without changing canonical per-byte profile coverage.
bool classicBlockListsEqual(List<Uint8List> first, List<Uint8List> second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i].length != second[i].length) return false;
    for (var j = 0; j < first[i].length; j++) {
      if (first[i][j] != second[i][j]) return false;
    }
  }
  return true;
}
