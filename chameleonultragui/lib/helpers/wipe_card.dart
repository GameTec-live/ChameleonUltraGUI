import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';

class WipeTarget {
  final CardData card;
  final TagType type;
  final MifareClassicType classicType;
  const WipeTarget(
    this.card,
    this.type, [
    this.classicType = MifareClassicType.none,
  ]);

  String get name => classicType != MifareClassicType.none
      ? 'MIFARE Classic ${classicType.name}'
      : type.name;
}

/// Wipes writable memory only: manufacturer, OTP, lock and counter areas stay intact.
class CardWiper {
  final ChameleonCommunicator communicator;
  CardWiper(this.communicator);

  Future<void> prepare() async {
    if (!await communicator.isReaderDeviceMode()) {
      await communicator.setReaderDeviceMode(true);
    }
  }

  Future<WipeTarget?> detect() async {
    await prepare();
    final card = await communicator.scan14443aTag();
    if (card == null) return null;
    if (await communicator.detectMf1Support()) {
      final type = await mfClassicGetType(communicator);
      if (type == MifareClassicType.none) {
        throw StateError('Unsupported Classic capacity');
      }
      return WipeTarget(card, TagType.unknown, type);
    }
    if (card.sak != 0) throw StateError('Unsupported card');
    final version = await mfUltralightGetVersion(communicator);
    // Accept only known product/storage combinations, never guess a write map.
    if (version.length == 8 && version[1] == 4) {
      final type = switch ((version[2], version[6])) {
        (3, 0x0B) => TagType.ultralight11,
        (3, 0x0E) => TagType.ultralight21,
        (4, 0x0B) => TagType.ntag210,
        (4, 0x0E) => TagType.ntag212,
        (4, 0x0F) => TagType.ntag213,
        (4, 0x11) => TagType.ntag215,
        (4, 0x13) => TagType.ntag216,
        _ => TagType.unknown,
      };
      if (type != TagType.unknown) return WipeTarget(card, type);
    } else if (version.length < 8) {
      if (await mfUltralightIsUlc(communicator)) {
        return WipeTarget(card, TagType.ultralightC);
      }
      // Original Ultralight wraps within a valid READ; starting at page 16 NAKs.
      final first = await _read(0);
      final wrapped = await _read(14);
      if (first.length == 16 &&
          wrapped.length == 16 &&
          bytesToHex(first.sublist(0, 8)) == bytesToHex(wrapped.sublist(8))) {
        return WipeTarget(card, TagType.ultralight);
      }
    }
    throw StateError('Unsupported or ambiguous card; no writes sent');
  }

  Future<void> checkTarget(WipeTarget target) async {
    await prepare();
    final current = await communicator.scan14443aTag();
    if (current == null ||
        bytesToHex(current.uid) != bytesToHex(target.card.uid)) {
      throw StateError('Card changed or removed; detect it again');
    }
  }

  Future<List<int>> wipeClassic(
    WipeTarget target,
    MifareClassicRecovery recovery,
    void Function(int) progress,
  ) async {
    await checkTarget(target);
    final writer = MifareClassicGen2WriteHelper(
      communicator,
      recovery: recovery,
    );
    final failed = <int>[];
    final count = mfClassicGetSectorCount(target.classicType);
    final trailer = hexToBytes('FFFFFFFFFFFFFF078069FFFFFFFFFFFF');
    for (var sector = 0; sector < count; sector++) {
      final last = mfClassicGetSectorTrailerBlockBySector(sector);
      // Restore access conditions before clearing data; never write block zero.
      try {
        if (!await writer.writeBlock(last, trailer, tryBothKeys: true)) {
          failed.add(last);
          continue;
        }
        recovery.validKeys[sector] = trailer.sublist(0, 6);
        recovery.validKeys[40 + sector] = trailer.sublist(10);
        final read = await communicator.mf1ReadBlock(
          last,
          0x60,
          trailer.sublist(0, 6),
        );
        if (read.length != 16 ||
            bytesToHex(read.sublist(6, 10)) != 'ff078069' ||
            bytesToHex(read.sublist(10)) != 'ffffffffffff') {
          failed.add(last);
          continue;
        }
        for (
          var block = mfClassicGetFirstBlockCountBySector(sector);
          block < last;
          block++
        ) {
          if (block == 0) continue;
          if (!await writer.writeBlock(
                block,
                Uint8List(16),
                tryBothKeys: true,
              ) ||
              bytesToHex(
                    await communicator.mf1ReadBlock(
                      block,
                      0x60,
                      trailer.sublist(0, 6),
                    ),
                  ) !=
                  bytesToHex(Uint8List(16))) {
            failed.add(block);
          }
        }
      } catch (_) {
        failed.add(last);
      } finally {
        progress(((sector + 1) / count * 100).round());
      }
    }
    return failed;
  }

  Future<Uint8List> _read(int page, {bool select = true}) =>
      communicator.send14ARaw(
        Uint8List.fromList([0x30, page]),
        autoSelect: select,
        keepRfField: true,
      );

  Future<void> _write(int page, List<int> data) async {
    final ack = await communicator.send14ARaw(
      Uint8List.fromList([0xA2, page, ...data]),
      autoSelect: false,
      keepRfField: true,
      checkResponseCrc: false,
    );
    if (ack.length != 1 || ack[0] != 0x0A) {
      throw StateError('Page $page rejected the write');
    }
  }

  Future<List<int>> wipeUltralight(
    WipeTarget target,
    Uint8List? key,
    void Function(int) progress,
  ) async {
    await checkTarget(target);
    if (target.type == TagType.ultralightC) {
      return _wipeUlc(key, progress);
    }
    final pwd = mfUltralightGetPasswordPage(target.type);
    if (key != null && pwd != 0) {
      // One supplied credential only: guessing may exhaust AUTHLIM permanently.
      final pack = await communicator.send14ARaw(
        Uint8List.fromList([0x1B, ...key]),
        keepRfField: true,
      );
      if (pack.length != 2) throw StateError('Password rejected');
    }
    final failed = <int>[];
    // NTAG/EV1 config is followed by PWD and PACK. Preserve reserved bytes.
    if (pwd != 0) {
      final config = await _read(pwd - 2, select: key == null);
      if (config.length != 16) {
        throw StateError(
          'Cannot read configuration; supply the current password',
        );
      }
      final cfg0 = config.sublist(0, 4)..[3] = 0xFF;
      final cfg1 = config.sublist(4, 8)..[0] = config[4] & 0x40;
      // CFGLCK cannot be undone. Mirror/counter/protection features are disabled.
      cfg0[0] = 0;
      cfg0[2] = 0;
      await _write(pwd - 2, cfg0);
      await _write(pwd - 1, cfg1);
      await _write(pwd, [255, 255, 255, 255]);
      await _write(pwd + 1, [0, 0, 0, 0]);
      final restored = await _read(pwd - 2, select: false);
      if (restored.length != 16 ||
          bytesToHex(restored.sublist(0, 8)) !=
              bytesToHex(Uint8List.fromList([...cfg0, ...cfg1]))) {
        throw StateError('Configuration verification failed');
      }
      await communicator.scan14443aTag();
      final pack = await communicator.send14ARaw(
        hexToBytes('1BFFFFFFFF'),
        keepRfField: true,
      );
      if (bytesToHex(pack) != '0000') {
        throw StateError('Default password verification failed');
      }
    }
    if (pwd == 0) await _read(0);
    final end = pwd == 0
        ? 16
        : switch (target.type) {
            TagType.ultralight11 || TagType.ntag210 => 16,
            _ => pwd - 3, // dynamic lock page is not user data
          };
    for (var page = 4; page < end; page++) {
      try {
        await _write(page, [0, 0, 0, 0]);
        final read = await communicator.send14ARaw(
          Uint8List.fromList([0x30, page]),
          autoSelect: false,
          keepRfField: true,
        );
        if (read.length != 16 || read.take(4).any((b) => b != 0)) {
          failed.add(page);
        }
      } catch (_) {
        failed.add(page);
        break; // Do not continue after losing the authenticated RF session.
      }
      progress(((page - 3) / (end - 4) * 100).round());
    }
    return failed;
  }

  Future<List<int>> _wipeUlc(
    Uint8List? supplied,
    void Function(int) progress,
  ) async {
    final defaultKey = hexToBytes('425245414B4D454946594F5543414E21');
    final key = supplied ?? defaultKey;
    if (!await communicator.mf0UlcAuth(key)) {
      throw StateError('Ultralight C key rejected');
    }
    // AUTH0=0x30 disables protection; AUTH1=1 is write-only protection if enabled.
    for (final (page, data) in [
      (0x2A, [0x30, 0, 0, 0]),
      (0x2B, [1, 0, 0, 0]),
    ]) {
      if (!await communicator.mf0UlcWritePage(
        key,
        page,
        Uint8List.fromList(data),
      )) {
        throw StateError('Configuration page $page rejected the write');
      }
    }
    final config = await communicator.mf0UlcReadPages(key, 0x2A, 2);
    if (bytesToHex(config) != '3000000001000000') {
      throw StateError('Ultralight C configuration verification failed');
    }
    final failed = <int>[];
    for (var page = 4; page < 0x28; page++) {
      if (!await communicator.mf0UlcWritePage(key, page, Uint8List(4)) ||
          bytesToHex(await communicator.mf0UlcReadPages(key, page, 1)) !=
              '00000000') {
        failed.add(page);
      }
      progress(((page - 3) / 36 * 100).round());
    }
    if (!await communicator.mf0UlcSetKey(key, defaultKey) ||
        !await communicator.mf0UlcAuth(defaultKey)) {
      failed.add(0x2C);
    }
    return failed;
  }

  /// Firmware acknowledges transmission only; it cannot identify/read back T55xx.
  Future<void> wipeT55xx({Uint8List? password, bool wipeData = true}) async {
    await prepare();
    if (!(await communicator.getDeviceCapabilities()).contains(
      ChameleonCommand.writeT55XX.value,
    )) {
      throw StateError('Firmware does not support raw T55xx writes');
    }
    // RF/64 Manchester, max block 2, no PWD/AOR/locks. Disable PWD BEFORE
    // clearing block 7, otherwise the password changes mid-operation.
    await communicator.writeT55XX(
      0,
      hexToBytes('00148040'),
      password: password,
    );
    await communicator.writeT55XX(7, Uint8List(4));
    if (wipeData) {
      for (var block = 1; block <= 6; block++) {
        await communicator.writeT55XX(block, Uint8List(4));
      }
    }
  }
}
