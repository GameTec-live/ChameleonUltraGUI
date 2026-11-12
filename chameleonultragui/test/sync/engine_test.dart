import 'dart:convert';

import 'package:chameleonultragui/sync/backend.dart';
import 'package:chameleonultragui/sync/crypto.dart';
import 'package:chameleonultragui/sync/engine.dart';
import 'package:chameleonultragui/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

String card(String id, String name) => jsonEncode({'id': id, 'name': name});

void main() {
  late MemoryBackend backend;
  late Keychain keychain;
  var wall = 1000;

  SyncEngine device(
    String name,
    MemorySource source, {
    bool bootstrapped = true,
  }) => SyncEngine(
    source: source,
    backend: backend,
    vaultId: 'vault',
    keychain: keychain,
    hlc: Hlc(name, now: () => wall++),
    ledger: SyncLedger({}, bootstrapped: bootstrapped),
  );

  setUp(() {
    backend = MemoryBackend();
    keychain = Keychain.create();
  });

  test(
    'edits and deletions propagate and the server sees only ciphertext',
    () async {
      final a = MemorySource(), b = MemorySource();
      final engineA = device('a', a), engineB = device('b', b);
      a.write('cards', 'c1', card('c1', 'Office badge'));
      a.write('settings', 'app_theme', '2');
      await engineA.sync();
      expect(await engineB.sync(), {'cards', 'settings'});
      expect(b.data['cards'], a.data['cards']);
      expect(b.data['settings'], {'app_theme': '2'});
      for (final (_, blob) in backend.records.values) {
        expect(
          utf8.decode(blob, allowMalformed: true),
          isNot(contains('Office')),
        );
      }

      b.write('cards', 'c1', null);
      await engineB.sync();
      await engineA.sync();
      expect(a.data['cards'], isEmpty);
    },
  );

  test('concurrent edits converge on the later write', () async {
    final a = MemorySource(), b = MemorySource();
    final engineA = device('a', a), engineB = device('b', b);
    a.write('cards', 'c1', card('c1', 'v1'));
    await engineA.sync();
    await engineB.sync();

    a.write('cards', 'c1', card('c1', 'from a'));
    engineA.scan(); // a edits first...
    b.write('cards', 'c1', card('c1', 'from b'));
    await engineB.sync(); // ...but b edits later and pushes first
    await engineA.sync(); // a's push conflicts, pulls, keeps b's newer edit
    await engineB.sync();
    expect(a.data['cards']!['c1'], card('c1', 'from b'));
    expect(b.data['cards']!['c1'], card('c1', 'from b'));
  });

  test('data from before sync loses to the vault on first contact', () async {
    final a = MemorySource(), b = MemorySource();
    a.write('settings', 'app_theme', '1');
    await device('a', a).sync();
    b.write('settings', 'app_theme', '2');
    b.write('cards', 'local', card('local', 'only on b'));
    await device('b', b, bootstrapped: false).sync();
    expect(b.data['settings'], {'app_theme': '1'});
    expect(b.data['cards']!.keys, ['local']); // still uploaded
    await device('a2', a).sync();
    expect(a.data['cards']!.keys, ['local']);
  });

  test('history restores a deleted record', () async {
    final a = MemorySource();
    final engine = device('a', a);
    a.write('cards', 'c1', card('c1', 'Gym'));
    await engine.sync();
    a.write('cards', 'c1', null);
    await engine.sync();

    final versions = await engine.history('cards', 'c1');
    expect(versions.map((v) => v.value), [null, card('c1', 'Gym')]);
    engine.restore('cards', 'c1', versions.last.value);
    await engine.sync();
    expect(a.data['cards']!['c1'], card('c1', 'Gym'));
    expect(engine.recent().first.$3.label, 'Gym');
  });

  test('membership records under an old key are ignored', () async {
    final a = MemorySource(), b = MemorySource();
    final engineA = device('a', a), engineB = device('b', b);
    final old = keychain;
    keychain = keychain.rotated();
    engineB.keychain = keychain;
    // A revoked device still holding the old key writes a fake device.
    a.write('_devices', 'evil', jsonEncode({'name': 'Evil', 'pub': 'x'}));
    engineA.keychain = old;
    await engineA.sync();
    await engineB.sync();
    expect(b.data['_devices'], isEmpty);
  });

  test('local edits made while pulling win over the pulled value', () async {
    final a = MemorySource(), b = MemorySource();
    final engineA = device('a', a), engineB = device('b', b);
    a.write('cards', 'c1', card('c1', 'Office'));
    await engineA.sync();
    await engineB.sync();
    a.write('cards', 'c1', card('c1', 'From A'));
    await engineA.sync();
    backend.onPull = () {
      backend.onPull = null;
      b.write('cards', 'c1', card('c1', 'From B'));
    };
    await engineB.sync();
    await engineA.sync();
    expect(b.data['cards']!['c1'], card('c1', 'From B'));
    expect(a.data['cards']!['c1'], card('c1', 'From B'));
  });

  test('records under a newer key wait for the new keychain', () async {
    final a = MemorySource(), b = MemorySource();
    final engineA = device('a', a), engineB = device('b', b);
    engineA.keychain = keychain.rotated();
    a.write('cards', 'c1', card('c1', 'Office'));
    await engineA.sync();
    await expectLater(
      engineB.sync(),
      throwsA(isA<SyncException>().having((e) => e.code, 'code', 'epoch')),
    );
    engineB.keychain = engineA.keychain;
    expect(await engineB.sync(), {'cards'});
    expect(b.data['cards'], a.data['cards']);
  });
}
