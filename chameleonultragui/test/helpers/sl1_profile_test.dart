import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';
import 'package:chameleonultragui/helpers/sl1_profile_uploader.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';

Sl1Profile fixture({String type = 'mini'}) => Sl1Profile.fromJson({
  'format': 'chameleon-sl1-profile',
  'version': 1,
  'name': 'Synthetic',
  'hf14a': {'uid': '01020304', 'atqa': '0400', 'sak': '08', 'ats': '0275'},
  'classic': {
    'type': type,
    'provenance': 'synthetic',
    'blocks': List.generate(
      Sl1Profile.counts[type]!,
      (i) => {
        'data': (i < 128 ? i % 4 == 3 : (i - 128) % 16 == 15)
            ? 'FFFFFFFFFFFFFF078069FFFFFFFFFFFF'
            : '00' * 16,
        'status': 'imported',
        'key': null,
        'errors': [],
      },
    ),
    'keys': List.generate(
      Sl1Profile.sectors[type]!,
      (_) => {
        'a': {'value': 'FFFFFFFFFFFF', 'status': 'provided', 'evidence': null},
        'b': {'value': 'FFFFFFFFFFFF', 'status': 'provided', 'evidence': null},
      },
    ),
  },
  'cardAuth': {
    'enabled': true,
    'scenario': 'sl1-cardauth-9004',
    'keyNumber': 36868,
    'key': '00112233445566778899AABBCCDDEEFF',
    'verification': {'status': 'provided', 'evidence': null},
  },
});
void main() {
  test('all geometries round trip with credential and coverage', () {
    for (final type in Sl1Profile.counts.keys) {
      final p = fixture(type: type);
      expect(
        Sl1Profile.parse(p.export()).image().length,
        Sl1Profile.counts[type],
      );
      final card = sl1ToCard(p);
      card.folderId = 'folder';
      final copy = CardSave.fromJson(card.toJson());
      expect(copy.sl1Profile!.export(), p.export());
      expect(copy.folderId, 'folder');
    }
  });
  test('unknown byte is distinct from zero; key merge is explicit', () {
    final p = fixture();
    p.json['classic']['blocks'][0]['data'] = '??' * 16;
    expect(() => p.image(), throwsFormatException);
    p.json['classic']['blocks'][0]['data'] = '00' * 16;
    p.json['classic']['blocks'][3]['data'] = '${'??' * 6}FF078069${'??' * 6}';
    expect(p.image()[0], everyElement(0));
    expect(p.image()[3].first, 255);
    p.json['classic']['keys'][0]['a']['value'] = '000000000000';
    p.json['classic']['blocks'][3]['data'] = 'FFFFFFFFFFFFFF078069FFFFFFFFFFFF';
    expect(() => p.image(), throwsFormatException);
  });
  test('strict schema, versions, ATS and access bits', () {
    final p = fixture();
    p.json['extra'] = 1;
    expect(() => Sl1Profile.fromJson(p.json), throwsFormatException);
    final q = fixture();
    q.json['version'] = 2;
    expect(() => Sl1Profile.fromJson(q.json), throwsFormatException);
    final r = fixture();
    r.json['hf14a']['ats'] = '0375';
    expect(() => Sl1Profile.fromJson(r.json), throwsFormatException);
    final s = fixture();
    s.json['classic']['blocks'][3]['data'] = '00' * 16;
    expect(() => s.image(), throwsFormatException);
  });
  test('nonempty ATS contains TL and T0 before upload', () async {
    for (final enabled in <bool?>[null, false, true]) {
      final p = fixture();
      if (enabled == null) {
        p.json['cardAuth'] = null;
      } else {
        p.json['cardAuth']['enabled'] = enabled;
      }
      p.json['hf14a']['ats'] = '01';
      expect(() => Sl1Profile.fromJson(p.json), throwsFormatException);
      final commands = <int>[];
      final uploader = Sl1Uploader((command, payload) async {
        commands.add(command);
        return Uint8List(0);
      }, () async => [for (var c = 4045; c <= 4051; c++) c]);
      await expectLater(uploader.upload(p, 3), throwsFormatException);
      expect(commands, isEmpty);
    }
    for (final ats in <String?>[null, '', '0278', 'FE${'00' * 253}']) {
      final p = fixture();
      p.json['cardAuth'] = null;
      p.json['hf14a']['ats'] = ats;
      expect(Sl1Profile.fromJson(p.json).json['hf14a']['ats'], ats);
    }
  });
  test('uploader exact BEGIN prefix and absolute chunk offsets', () async {
    final commands = <int>[];
    final payloads = <List<int>>[];
    final uploader = Sl1Uploader((c, p) async {
      commands.add(c);
      payloads.add(p);
      return c == 4045
          ? Uint8List.fromList([1, p[1], ...List.filled(12, 0)])
          : p;
    }, () async => [for (var c = 4045; c <= 4051; c++) c]);
    await uploader.upload(fixture(), 6);
    expect(commands, [4045, 4046, 4047, 4047, 4047, 4048]);
    expect(payloads[1].length, 38);
    expect(payloads[1].sublist(0, 5), [1, 6, 3, 232, 4]);
    expect(payloads[1].sublist(36), [2, 0x75]);
    expect(payloads[2].sublist(0, 4), [1, 6, 0, 0]);
    expect(payloads[3].sublist(0, 4), [1, 6, 0, 8]);
    expect(payloads[4].sublist(0, 4), [1, 6, 0, 16]);
  });
  test('incomplete or unsupported profile never mutates device', () async {
    final commands = <int>[];
    final uploader = Sl1Uploader((c, p) async {
      commands.add(c);
      return c == 4045
          ? Uint8List.fromList([1, p[1], ...List.filled(12, 0)])
          : p;
    }, () async => []);
    await expectLater(uploader.upload(fixture(), 0), throwsUnsupportedError);
    expect(commands, isEmpty);
    final p = fixture();
    p.json['classic']['blocks'][0]['data'] = '??' * 16;
    await expectLater(uploader.upload(p, 0), throwsFormatException);
    expect(commands, isEmpty);
  });
  test('SAVE failure is surfaced with no automatic cancel or retry', () async {
    final commands = <int>[];
    final uploader = Sl1Uploader((c, p) async {
      commands.add(c);
      if (c == 4048) throw StateError('stage 5');
      return c == 4045
          ? Uint8List.fromList([1, p[1], ...List.filled(12, 0)])
          : p;
    }, () async => [for (var c = 4045; c <= 4051; c++) c]);
    await expectLater(uploader.upload(fixture(), 0), throwsStateError);
    expect(commands.last, 4048);
    expect(commands.where((c) => c == 4048).length, 1);
    expect(commands, isNot(contains(4049)));
  });
  test(
    'legacy coverage remains unverified through local edits and folders',
    () {
      final card = sl1ToCard(fixture());
      card.sl1Profile = null;
      final legacy = legacySl1(card);
      expect(() => legacy.image(), throwsFormatException);
      card.sl1Profile = legacy;
      card.folderId = 'yellow';
      card.name = 'Renamed';
      reconcileSl1(card);
      final copy = CardSave.fromJson(card.toJson());
      expect(
        copy.sl1Profile!.json['classic']['provenance'],
        'legacy-unverified',
      );
      expect(copy.folderId, 'yellow');
      expect(copy.sl1Profile!.json['name'], 'Renamed');
    },
  );
  test('read failures and per-byte unknown coverage survive interchange', () {
    final p = fixture();
    p.json['classic']['blocks'][0] = {
      'data': '00' * 15 + '??',
      'status': 'read',
      'key': 'B',
      'errors': [
        {'key': 'A', 'status': 6, 'reason': 'Authentication failed'},
      ],
    };
    final q = Sl1Profile.parse(p.export());
    expect(q.json['classic']['blocks'][0]['errors'][0]['status'], 6);
    expect(q.json['classic']['blocks'][0]['data'], '00' * 15 + '??');
    expect(() => q.image(), throwsFormatException);
  });
  test('duplicate fields including escaped names are rejected', () {
    final source = fixture().export();
    expect(
      () => Sl1Profile.parse(
        source.replaceFirst('"version": 1', '"version": 1, "version": 1'),
      ),
      throwsFormatException,
    );
    expect(
      () => Sl1Profile.parse(
        source.replaceFirst('"version": 1', r'"version": 1, "versi\u006fn": 1'),
      ),
      throwsFormatException,
    );
  });
  test(
    'write interruption never saves and malformed status never begins',
    () async {
      final calls = <int>[];
      final uploader = Sl1Uploader((c, p) async {
        calls.add(c);
        if (c == 4047) throw StateError('Disconnected');
        return Uint8List.fromList([1, p[1], ...List.filled(12, 0)]);
      }, () async => [for (var c = 4045; c <= 4051; c++) c]);
      await expectLater(uploader.upload(fixture(), 3), throwsStateError);
      expect(calls, [4045, 4046, 4047]);
      calls.clear();
      final malformed = Sl1Uploader((c, p) async {
        calls.add(c);
        return Uint8List(0);
      }, () async => [for (var c = 4045; c <= 4051; c++) c]);
      await expectLater(malformed.upload(fixture(), 3), throwsFormatException);
      expect(calls, [4045]);
    },
  );
  test('control commands explicitly address the selected slot', () async {
    final calls = <List<int>>[];
    final uploader = Sl1Uploader((c, p) async {
      calls.add([c, ...p]);
      return Uint8List.fromList([1, p[1], ...List.filled(12, 0)]);
    }, () async => [for (var c = 4045; c <= 4051; c++) c]);
    await uploader.status(3);
    await uploader.setEnabled(3, true);
    await uploader.setEnabled(3, false);
    await uploader.cancel(3);
    await uploader.clear(3);
    expect(calls, [
      [4045, 1, 3],
      [4051, 1, 3, 1],
      [4051, 1, 3, 0],
      [4049, 1, 3],
      [4050, 1, 3],
    ]);
  });
}
