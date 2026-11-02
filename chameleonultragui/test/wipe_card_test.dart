import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';

import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/wipe_card.dart';
import 'package:chameleonultragui/gui/menu/tools/wipe_card.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class _Card extends ChameleonCommunicator {
  _Card() : super(Logger(level: Level.off));
  final writes = <(int, List<int>, List<int>?)>[];
  final pages = List.generate(256, (_) => Uint8List(4));
  int storage = 0x0F;
  bool originalUltralight = false;
  bool simulateMirror = false;
  bool present = true;
  bool supported = true;
  bool authenticated = false;
  bool protected = false;
  int? reject;
  String uid = '01020304050607';

  @override
  Future<bool> isReaderDeviceMode() async => true;
  @override
  Future<List<int>> getDeviceCapabilities() async =>
      supported ? [ChameleonCommand.writeT55XX.value] : [];
  @override
  Future<CardData?> scan14443aTag() async {
    authenticated = false;
    return present
        ? CardData(
            uid: hexToBytes(uid),
            sak: 0,
            atqa: hexToBytes('0044'),
            ats: Uint8List(0),
          )
        : null;
  }

  @override
  Future<bool> detectMf1Support() async => false;
  @override
  Future<void> writeT55XX(
    int block,
    Uint8List word, {
    Uint8List? password,
    bool page1 = false,
  }) async {
    writes.add((block, word.toList(), password?.toList()));
  }

  @override
  Future<Uint8List> send14ARaw(
    Uint8List data, {
    int respTimeoutMs = 100,
    int? bitLen,
    bool activateRfField = true,
    bool waitResponse = true,
    bool appendCrc = true,
    bool autoSelect = true,
    bool keepRfField = false,
    bool checkResponseCrc = true,
  }) async {
    if (autoSelect) authenticated = false;
    if (data[0] == 0x60 && originalUltralight) return Uint8List(0);
    if (data[0] == 0x60) {
      return Uint8List.fromList([0, 4, 4, 2, 1, 0, storage, 3]);
    }
    if (data[0] == 0x1B) {
      authenticated = true;
      return Uint8List(2);
    }
    if (protected && !authenticated) throw StateError('Authentication lost');
    if (data[0] == 0x30) {
      if (originalUltralight && data[1] >= 16) return Uint8List.fromList([0]);
      final read = Uint8List.fromList([
        for (var i = 0; i < 4; i++)
          ...pages[originalUltralight ? (data[1] + i) % 16 : data[1] + i],
      ]);
      if (simulateMirror &&
          (pages[41][0] & 0xC0) != 0 &&
          data[1] == pages[41][2]) {
        read[0] = 0x30; // UID ASCII replaces the physical EEPROM zero.
      }
      return read;
    }
    if (data[0] == 0xA2) {
      writes.add((data[1], data.sublist(2), null));
      if (data[1] == reject) return Uint8List.fromList([0]);
      pages[data[1]] = data.sublist(2);
      return Uint8List.fromList([0x0A]);
    }
    return Uint8List(0);
  }
}

class _Classic extends _Card {
  final blocks = List.generate(20, (_) => Uint8List(16));
  @override
  Future<bool> mf1WriteBlock(
    int block,
    int keyType,
    Uint8List key,
    Uint8List data,
  ) async {
    writes.add((block, data.toList(), key.toList()));
    if (block == reject) return false;
    blocks[block] = data;
    return true;
  }

  @override
  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async =>
      blocks[block];
}

class _Ulc extends _Card {
  Uint8List? newKey;
  @override
  Future<bool> mf0UlcAuth(Uint8List key) async => true;
  @override
  Future<bool> mf0UlcWritePage(Uint8List key, int page, Uint8List data) async {
    writes.add((page, data.toList(), key.toList()));
    if (page == reject) return false;
    pages[page] = data;
    return true;
  }

  @override
  Future<Uint8List> mf0UlcReadPages(Uint8List key, int page, int count) async =>
      Uint8List.fromList([for (var i = 0; i < count; i++) ...pages[page + i]]);
  @override
  Future<bool> mf0UlcSetKey(Uint8List oldKey, Uint8List key) async {
    newKey = key;
    return true;
  }
}

void main() {
  test(
    'original Ultralight detection uses a valid starting page with rollover',
    () async {
      final card = _Card()..originalUltralight = true;
      for (var page = 0; page < 16; page++) {
        card.pages[page].fillRange(0, 4, page + 1);
      }
      final wiper = CardWiper(card);
      final target = (await wiper.detect())!;
      expect(target.type, TagType.ultralight);
      expect(card.writes, isEmpty);
      expect(await wiper.wipeUltralight(target, null, (_) {}), isEmpty);
      expect(card.writes.map((w) => w.$1), [for (var p = 4; p < 16; p++) p]);
      expect(card.pages[3], [4, 4, 4, 4]);
    },
  );

  test('Classic restores trailers, skips manufacturer block and reports inaccessible sectors', () async {
    final card = _Classic();
    final target = WipeTarget(
      (await card.scan14443aTag())!,
      TagType.unknown,
      MifareClassicType.mini,
    );
    final recovery = MifareClassicRecovery(
      appState: ChameleonGUIState(SharedPreferencesProvider()),
      update: () {},
      localizations: lookupAppLocalizations(const Locale('en')),
      validKeys: List.generate(80, (_) => hexToBytes('FFFFFFFFFFFF')),
    );
    final wiper = CardWiper(card);
    expect(await wiper.wipeClassic(target, recovery, (_) {}), isEmpty);
    expect(card.writes.map((w) => w.$1), [
      3,
      1,
      2,
      7,
      4,
      5,
      6,
      11,
      8,
      9,
      10,
      15,
      12,
      13,
      14,
      19,
      16,
      17,
      18,
    ]);
    expect(bytesToHex(card.blocks[3]), 'ffffffffffffff078069ffffffffffff');
    expect(card.writes.any((w) => w.$1 == 0), isFalse);
    card.writes.clear();
    card.reject = 7;
    expect(await wiper.wipeClassic(target, recovery, (_) {}), [7]);
    expect(card.writes.any((w) => [4, 5, 6].contains(w.$1)), isFalse);
  });

  test('Ultralight C resets access and logical 3DES key, preserves lock/counter/OTP pages', () async {
    final card = _Ulc();
    final target = WipeTarget(
      (await card.scan14443aTag())!,
      TagType.ultralightC,
    );
    expect(await CardWiper(card).wipeUltralight(target, null, (_) {}), isEmpty);
    expect(card.writes.map((w) => w.$1), [
      for (var i = 4; i < 40; i++) i,
      42,
      43,
    ]);
    expect(bytesToHex(card.newKey!), '425245414b4d454946594f5543414e21');
  });

  test(
    'failed NTAG and ULC erasure retains original protection and credentials',
    () async {
      final card = _Card()..protected = true;
      final target = WipeTarget((await card.scan14443aTag())!, TagType.ntag213);
      card.reject = 4;
      expect(
        await CardWiper(card)
            .wipeUltralight(target, hexToBytes('12345678'), (_) {}),
        [for (var p = 4; p < 40; p++) p],
      );
      expect(card.writes.map((w) => w.$1), [4]);
      final ulc = _Ulc()..reject = 4;
      final ulcTarget = WipeTarget(
        (await ulc.scan14443aTag())!,
        TagType.ultralightC,
      );
      expect(await CardWiper(ulc).wipeUltralight(ulcTarget, null, (_) {}), [4]);
      expect(ulc.newKey, isNull);
      expect(ulc.writes.any((w) => w.$1 >= 40), isFalse);
    },
  );

  test(
    'locked NTAG config does not prevent user erasure and is reported',
    () async {
      final card = _Card();
      card.pages[42][0] = 0x40;
      card.reject = 41;
      final target = (await CardWiper(card).detect())!;
      expect(await CardWiper(card).wipeUltralight(target, null, (_) {}), [
        41,
        42,
      ]);
      expect(card.writes.map((w) => w.$1), [
        for (var p = 4; p < 40; p++) p,
        43,
        44,
      ]);
      expect(card.pages[42][0], 0x40);
    },
  );

  test(
    'active NTAG mirroring is disabled without opening access before erase',
    () async {
      final card = _Card()
        ..simulateMirror = true
        ..protected = true;
      card.pages[41] = Uint8List.fromList([0x44, 0, 4, 4]);
      card.pages[43] = hexToBytes('12345678');
      final target = (await CardWiper(card).detect())!;
      expect(
        await CardWiper(card)
            .wipeUltralight(target, hexToBytes('12345678'), (_) {}),
        isEmpty,
      );
      expect(card.writes.first.$1, 41);
      expect(card.writes.first.$2, [4, 0, 4, 4]);
      expect(card.writes.skip(1).take(36).map((w) => w.$1), [
        for (var p = 4; p < 40; p++) p,
      ]);
      expect(card.writes.skip(37).map((w) => w.$1), [41, 42, 43, 44]);
    },
  );

  test('T55xx opens config before clearing password, optional data, capability gate', () async {
    final card = _Card();
    final wiper = CardWiper(card);
    await wiper.wipeT55xx(password: hexToBytes('12345678'));
    expect(card.writes.map((w) => w.$1), [0, 7, 1, 2, 3, 4, 5, 6]);
    expect(card.writes.first.$1, 0);
    expect(card.writes.first.$2, [0, 0x14, 0x80, 0x40]);
    expect(card.writes.first.$3, [0x12, 0x34, 0x56, 0x78]);
    expect(
      card.writes
          .skip(1)
          .every((w) => w.$3 == null && w.$2.every((b) => b == 0)),
      isTrue,
    );
    card.writes.clear();
    await wiper.wipeT55xx(wipeData: false);
    expect(card.writes.map((w) => w.$1), [0, 7]);
    card.writes.clear();
    card.supported = false;
    await expectLater(wiper.wipeT55xx(), throwsStateError);
    expect(card.writes, isEmpty);
  });

  for (final (storage, pwd) in [(0x0F, 43), (0x11, 133), (0x13, 229)]) {
    test(
      'NTAG $storage uses correct map, keeps auth and preserves lock/OTP/UID',
      () async {
        final card = _Card();
        card.storage = storage;
        for (final page in card.pages) {
          page.fillRange(0, 4, 0xAB);
        }
        card.pages[pwd - 2][0] &= 0x3F; // Test non-mirrored maps separately.
        final wiper = CardWiper(card);
        final target = (await wiper.detect())!;
        card.protected = true;
        expect(
          await wiper.wipeUltralight(target, hexToBytes('12345678'), (_) {}),
          isEmpty,
        );
        expect(card.writes.skip(pwd - 7).map((w) => w.$1), [
          pwd - 2,
          pwd - 1,
          pwd,
          pwd + 1,
        ]);
        expect(card.pages[pwd - 2][3], 255);
        expect(card.pages[pwd - 1][0], 0);
        expect(card.pages[pwd], [255, 255, 255, 255]);
        expect(
          card.writes.take(pwd - 7).map((w) => w.$1),
          List.generate(pwd - 7, (i) => i + 4),
        );
        for (final page in [0, 1, 2, 3, pwd - 3]) {
          expect(card.pages[page], [0xAB, 0xAB, 0xAB, 0xAB]);
        }
      },
    );
  }

  test(
    'unknown versions, changed cards and rejected writes never report success',
    () async {
      final card = _Card()..storage = 0xFF;
      final wiper = CardWiper(card);
      await expectLater(wiper.detect(), throwsStateError);
      expect(card.writes, isEmpty);
      card.storage = 0x0F;
      final target = (await wiper.detect())!;
      card.uid = '07060504030201';
      await expectLater(
        wiper.wipeUltralight(target, null, (_) {}),
        throwsStateError,
      );
      expect(card.writes, isEmpty);
      card.uid = '01020304050607';
      card.reject = 4;
      expect(await wiper.wipeUltralight(target, null, (_) {}), [
        for (var p = 4; p < 40; p++) p,
      ]);
    },
  );

  testWidgets(
    'requires detection and destructive confirmation, reports verified result',
    (tester) async {
      final card = _Card();
      final app = ChameleonGUIState(SharedPreferencesProvider())
        ..communicator = card;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: WipeCardMenu()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Detect card'));
      await tester.tap(find.text('Detect card'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ntag213'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.text('I understand that the card data will be erased.'),
      );
      await tester.tap(
        find.text('I understand that the card data will be erased.'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Wipe verified.'), findsOneWidget);
      expect(card.writes, isNotEmpty);
    },
  );
}
