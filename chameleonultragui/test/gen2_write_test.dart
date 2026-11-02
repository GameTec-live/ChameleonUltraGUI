import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class _FakeChameleonCommunicator extends ChameleonCommunicator {
  final List<Uint8List> memory;
  final bool ignoreSector0TrailerWrite;

  _FakeChameleonCommunicator(
    this.memory, {
    this.ignoreSector0TrailerWrite = true,
  }) : super(Logger());

  @override
  Future<CardData?> scan14443aTag() async {
    return CardData(
      uid: Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
      sak: 0x08,
      atqa: Uint8List.fromList([0x00, 0x04]),
      ats: Uint8List(0),
    );
  }

  @override
  Future<bool> mf1WriteBlock(
      int block, int keyType, Uint8List key, Uint8List data) async {
    // Reproduce the observed failure mode: the device reports success for
    // sector 0's trailer write even though the protected trailer is unchanged.
    if (block == 3 && ignoreSector0TrailerWrite) {
      return true;
    }

    memory[block] = Uint8List.fromList(data);
    return true;
  }

  @override
  Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key) async {
    final data = Uint8List.fromList(memory[block]);

    if (block == 3) {
      // Key A is never returned when reading a sector trailer.
      data.fillRange(0, 6, 0);
    }

    return data;
  }

  @override
  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async {
    if (keyType != 0x61 || key.length != 6) {
      return false;
    }

    final storedKeyB = memory[block].sublist(10, 16);
    for (var index = 0; index < 6; index++) {
      if (storedKeyB[index] != key[index]) {
        return false;
      }
    }

    return true;
  }
}

Uint8List _keyA(int sector) =>
    Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, sector]);

Uint8List _readableKeyB(int sector) =>
    Uint8List.fromList([0xE0, 0xE1, 0xE2, 0xE3, 0xE4, sector]);

Uint8List _authKeyB(int sector) =>
    Uint8List.fromList([0xB0, 0xB1, 0xB2, 0xB3, 0xB4, sector]);

Uint8List _sourceTrailer(int sector) => Uint8List.fromList([
      ..._keyA(sector),
      0xFF,
      0x07,
      0x80,
      0x69,
      ..._readableKeyB(sector),
    ]);

void main() {
  testWidgets(
      'Gen2 write fails when trailer write is acknowledged but not applied',
      (tester) async {
    AppLocalizations? localizations;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            localizations = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(localizations, isNotNull);

    final source = List<Uint8List>.generate(
      4,
      (block) => Uint8List.fromList(List<int>.filled(16, block)),
    );

    source[3] = _sourceTrailer(0);

    // Source payload sentinel.
    source[1] = Uint8List.fromList(List<int>.filled(16, 0x01));

    final target = source
        .map((block) => Uint8List.fromList(block))
        .toList(growable: false);

    // Target payload differs so we can prove ordinary writes still occur.
    target[1] = Uint8List.fromList(List<int>.filled(16, 0xA5));

    // Sector 0 trailer condition 010:
    // data blocks remain writable, but the sector trailer is not writable.
    target[3] = Uint8List.fromList([
      ..._keyA(0),
      0x7F,
      0x0F,
      0x08,
      0x69,
      ..._readableKeyB(0),
    ]);

    final communicator = _FakeChameleonCommunicator(target);

    final appState = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator = communicator
      ..log = Logger();

    final checkMarks =
        List.filled(80, ChameleonKeyCheckmark.none, growable: false);
    final validKeys = List.generate(80, (_) => Uint8List(0), growable: false);
    final readableData =
        List.generate(80, (_) => Uint8List(0), growable: false);

    for (var sector = 0; sector < 16; sector++) {
      checkMarks[sector] = ChameleonKeyCheckmark.found;
      validKeys[sector] = _keyA(sector);

      checkMarks[40 + sector] = ChameleonKeyCheckmark.readable;
      readableData[40 + sector] = _readableKeyB(sector);
    }

    final recovery = MifareClassicRecovery(
      appState: appState,
      update: () {},
      localizations: localizations!,
      mifareClassicType: MifareClassicType.m1k,
      checkMarks: checkMarks,
      validKeys: validKeys,
      readableData: readableData,
    );

    final helper =
        MifareClassicGen2WriteHelper(communicator, recovery: recovery);

    final card = CardSave(
      uid: '12345678',
      name: 'Gen2 ACL verification fixture',
      tag: TagType.mifare1K,
      sak: 0x08,
      atqa: Uint8List.fromList([0x00, 0x04]),
      data: source,
    );

    final result = await tester.runAsync(() => helper.writeData(card, (_) {}));

    // Ordinary data write succeeded.
    expect(target[1], orderedEquals(source[1]));

    // The protected sector trailer did not actually change.
    expect(
      target[3],
      orderedEquals([
        ..._keyA(0),
        0x7F,
        0x0F,
        0x08,
        0x69,
        ..._readableKeyB(0),
      ]),
    );

    // An incomplete clone must not be reported as a complete success.
    expect(result, isFalse);
  });

  testWidgets('Gen2 write succeeds when trailer write is applied',
      (tester) async {
    AppLocalizations? localizations;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            localizations = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(localizations, isNotNull);

    final source = List<Uint8List>.generate(
      4,
      (block) => Uint8List.fromList(List<int>.filled(16, block)),
    );

    source[3] = _sourceTrailer(0);

    source[1] = Uint8List.fromList(List<int>.filled(16, 0x01));

    final target = source
        .map((block) => Uint8List.fromList(block))
        .toList(growable: false);

    target[1] = Uint8List.fromList(List<int>.filled(16, 0xA5));

    // Give sector 0 a different GPB so this test proves the trailer itself
    // was actually updated, not merely acknowledged.
    target[3] = Uint8List.fromList([
      ..._keyA(0),
      0xFF,
      0x07,
      0x80,
      0x68,
      ..._readableKeyB(0),
    ]);

    final communicator = _FakeChameleonCommunicator(
      target,
      ignoreSector0TrailerWrite: false,
    );

    final appState = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator = communicator
      ..log = Logger();

    final checkMarks =
        List.filled(80, ChameleonKeyCheckmark.none, growable: false);
    final validKeys = List.generate(80, (_) => Uint8List(0), growable: false);
    final readableData =
        List.generate(80, (_) => Uint8List(0), growable: false);

    for (var sector = 0; sector < 16; sector++) {
      checkMarks[sector] = ChameleonKeyCheckmark.found;
      validKeys[sector] = _keyA(sector);

      checkMarks[40 + sector] = ChameleonKeyCheckmark.readable;
      readableData[40 + sector] = _readableKeyB(sector);
    }

    final recovery = MifareClassicRecovery(
      appState: appState,
      update: () {},
      localizations: localizations!,
      mifareClassicType: MifareClassicType.m1k,
      checkMarks: checkMarks,
      validKeys: validKeys,
      readableData: readableData,
    );

    final helper =
        MifareClassicGen2WriteHelper(communicator, recovery: recovery);

    final card = CardSave(
      uid: '12345678',
      name: 'Gen2 successful write fixture',
      tag: TagType.mifare1K,
      sak: 0x08,
      atqa: Uint8List.fromList([0x00, 0x04]),
      data: source,
    );

    final result = await tester.runAsync(() => helper.writeData(card, (_) {}));

    expect(target[1], orderedEquals(source[1]));
    expect(target[3], orderedEquals(source[3]));
    expect(result, isTrue);
  });

  testWidgets('Gen2 write verifies protected Key B by authentication',
      (tester) async {
    AppLocalizations? localizations;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            localizations = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(localizations, isNotNull);

    final source = List<Uint8List>.generate(
      4,
      (block) => Uint8List.fromList(List<int>.filled(16, block)),
    );

    source[1] = Uint8List.fromList(List<int>.filled(16, 0x01));
    source[3] = Uint8List.fromList([
      ..._keyA(0),
      0xF7,
      0x8F,
      0x00,
      0x69,
      ..._authKeyB(0),
    ]);

    final target = source
        .map((block) => Uint8List.fromList(block))
        .toList(growable: false);

    target[1] = Uint8List.fromList(List<int>.filled(16, 0xA5));

    final communicator = _FakeChameleonCommunicator(
      target,
      ignoreSector0TrailerWrite: false,
    );

    final appState = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator = communicator
      ..log = Logger();

    final checkMarks =
        List.filled(80, ChameleonKeyCheckmark.none, growable: false);
    final validKeys = List.generate(80, (_) => Uint8List(0), growable: false);
    final readableData =
        List.generate(80, (_) => Uint8List(0), growable: false);

    checkMarks[0] = ChameleonKeyCheckmark.found;
    validKeys[0] = _keyA(0);
    checkMarks[40] = ChameleonKeyCheckmark.found;
    validKeys[40] = _authKeyB(0);

    final recovery = MifareClassicRecovery(
      appState: appState,
      update: () {},
      localizations: localizations!,
      mifareClassicType: MifareClassicType.m1k,
      checkMarks: checkMarks,
      validKeys: validKeys,
      readableData: readableData,
    );

    final helper =
        MifareClassicGen2WriteHelper(communicator, recovery: recovery);

    final card = CardSave(
      uid: '12345678',
      name: 'Gen2 protected Key B fixture',
      tag: TagType.mifare1K,
      sak: 0x08,
      atqa: Uint8List.fromList([0x00, 0x04]),
      data: source,
    );

    final result = await tester.runAsync(() => helper.writeData(card, (_) {}));

    expect(target[1], orderedEquals(source[1]));
    expect(target[3], orderedEquals(source[3]));
    expect(result, isTrue);
  });
}
