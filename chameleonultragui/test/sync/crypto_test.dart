import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/sync/bip39.dart';
import 'package:chameleonultragui/sync/crypto.dart';
import 'package:chameleonultragui/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bip39', () {
    test('matches the reference vectors', () {
      expect(
        entropyToMnemonic(Uint8List(32)),
        '${List.filled(23, 'abandon').join(' ')} art',
      );
      expect(
        entropyToMnemonic(Uint8List.fromList(List.filled(16, 0x7f))),
        'legal winner thank year wave sausage worth useful legal winner thank yellow',
      );
    });

    test('round-trips and rejects bad checksums or words', () {
      final entropy = randomBytes(32);
      final words = entropyToMnemonic(entropy);
      expect(mnemonicToEntropy('  ${words.toUpperCase()} '), entropy);
      final swapped = words.split(' ')
        ..[0] = words.split(' ')[0] == 'zoo' ? 'abandon' : 'zoo';
      expect(() => mnemonicToEntropy(swapped.join(' ')), throwsFormatException);
      expect(
        () =>
            mnemonicToEntropy('notaword ${words.split(' ').skip(1).join(' ')}'),
        throwsFormatException,
      );
    });
  });

  group('keychain', () {
    test(
      'sealed blobs open only for the same vault, key and keychain',
      () async {
        final keychain = Keychain.create();
        final blob = await keychain.seal('vault', 'key', utf8.encode('secret'));
        expect(Keychain.blobEpoch(blob), 1);
        expect(
          utf8.decode(await keychain.open('vault', 'key', blob)),
          'secret',
        );
        await expectLater(
          keychain.open('vault', 'other', blob),
          throwsA(anything),
        );
        await expectLater(
          keychain.open('other', 'key', blob),
          throwsA(anything),
        );
        await expectLater(
          Keychain.create().open('vault', 'key', blob),
          throwsA(anything),
        );
      },
    );

    test(
      'rotation keeps old epochs readable and the record keys stable',
      () async {
        final keychain = Keychain.create();
        final old = await keychain.seal('v', 'k', [1, 2, 3]);
        final rotated = keychain.rotated();
        expect(rotated.current, 2);
        expect(await rotated.open('v', 'k', old), [1, 2, 3]);
        expect(Keychain.blobEpoch(await rotated.seal('v', 'k', [4])), 2);
        expect(
          await rotated.recordKey('cards', 'a'),
          await keychain.recordKey('cards', 'a'),
        );
        final json = Keychain.fromJson(
          jsonDecode(jsonEncode(rotated.toJson())),
        );
        expect(await json.open('v', 'k', old), [1, 2, 3]);
      },
    );

    test('wrapped keychains open only for their member and epoch', () async {
      final member = Identity.random();
      final keychain = Keychain.create();
      final wrapped = await wrapKeychain(
        keychain,
        vaultId: 'v',
        memberId: 'm',
        memberPublicKey: await member.publicKey(),
      );
      final opened = await unwrapKeychain(
        wrapped,
        vaultId: 'v',
        memberId: 'm',
        epoch: 1,
        identity: member,
      );
      expect(opened.epochs[1], keychain.epochs[1]);

      Future<void> fails(Future<void> future) =>
          expectLater(future, throwsA(anything));
      await fails(
        unwrapKeychain(
          wrapped,
          vaultId: 'v',
          memberId: 'x',
          epoch: 1,
          identity: member,
        ),
      );
      await fails(
        unwrapKeychain(
          wrapped,
          vaultId: 'v',
          memberId: 'm',
          epoch: 2,
          identity: member,
        ),
      );
      await fails(
        unwrapKeychain(
          wrapped,
          vaultId: 'v',
          memberId: 'm',
          epoch: 1,
          identity: Identity.random(),
        ),
      );
    });

    test('recovery keys are deterministic per phrase', () async {
      final entropy = randomBytes(16);
      final a = await RecoveryKeys.derive(entropy);
      final b = await RecoveryKeys.derive(entropy);
      expect(a.vaultId, b.vaultId);
      expect(a.token, b.token);
      expect(await a.identity.publicKey(), await b.identity.publicKey());
      expect(
        (await RecoveryKeys.derive(randomBytes(16))).vaultId,
        isNot(a.vaultId),
      );
    });
  });

  test('hlc is monotonic and moves past observed timestamps', () {
    var wall = 1000;
    final clock = Hlc('a', now: () => wall);
    final first = clock.next();
    final second = clock.next();
    expect(second.compareTo(first), greaterThan(0));
    clock.observe(Hlc('b', now: () => 5000).next());
    expect(clock.next().compareTo('000000000005000-000000-b'), greaterThan(0));
    wall = 9000;
    expect(clock.next(), startsWith('000000000009000-000000'));
    expect(Hlc.zero.compareTo(first), lessThan(0));
  });
}
