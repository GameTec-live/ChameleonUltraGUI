import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class WeakCardSerial extends Fake implements AbstractSerial {
  @override
  ConnectionType get connectionType => ConnectionType.usb;
}

class WeakCardCommunicator extends ChameleonCommunicator {
  WeakCardCommunicator({required this.stable})
    : super(Logger(level: Level.off));

  final bool stable;
  var measurements = 0;
  final collectedLevels = <NTLevel>[];
  final checkedKeys = <String>[];
  static final knownKey = hexToBytes('FFFFFFFFFFFF');
  Uint8List get targetKey =>
      hexToBytes(stable ? '112233445566' : '405044544951');

  @override
  Future<NTLevel> getMf1NTLevel() async => NTLevel.weak;

  @override
  Future<List<int>> getDeviceCapabilities() async => [];

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    expect(cmd, ChameleonCommand.hf14ARawCommand);
    return ChameleonMessage(command: cmd.value, status: 0, data: Uint8List(0));
  }

  @override
  Future<NTDistance> getMf1NTDistance(
    int block,
    int keyType,
    Uint8List keyKnown,
  ) async {
    expect((block, keyType), (63, 0x60));
    expect(keyKnown, knownKey);
    measurements++;
    return NTDistance(
      uid: 0x11223344,
      distance: stable ? 613 : 1000 + measurements * 100,
    );
  }

  @override
  Future<NestedNonces> getMf1NestedNonces(
    int block,
    int keyType,
    Uint8List keyKnown,
    int targetBlock,
    int targetKeyType, {
    NTLevel level = NTLevel.weak,
    bool slow = false,
  }) async {
    expect((block, keyType, targetBlock, targetKeyType), (63, 0x60, 3, 0x60));
    expect(keyKnown, knownKey);
    collectedLevels.add(level);
    if (level == NTLevel.weak) {
      // Stable captures are 613 clocks apart. Unstable captures use the
      // 36892/33619 distances observed on the attached card.
      return NestedNonces(
        nonces: [
          NestedNonce(
            nt: 680314570,
            ntEnc: stable ? 777166916 : 1983322505,
            parity: stable ? 7 : 2,
          ),
          NestedNonce(
            nt: 3450034482,
            ntEnc: stable ? 1996614342 : 3813075436,
            parity: stable ? 6 : 1,
          ),
        ],
      );
    }
    expect(level, NTLevel.hard);
    final bytes = await File('test/native/fixtures/hardnested-filtering.bin')
        .readAsBytes();
    final data = ByteData.sublistView(bytes);
    return NestedNonces(
      nonces: [
        for (var i = 6; i < bytes.length; i += 9)
          NestedNonce(
            nt: data.getUint32(i),
            ntEnc: data.getUint32(i + 4),
            parity: bytes[i + 8],
          ),
      ],
    );
  }

  @override
  Future<Uint8List?> mf1AuthMultipleKeys(
    int block,
    int keyType,
    List<Uint8List> keys,
  ) async {
    expect((block, keyType), (3, 0x60));
    // Failed weak captures must never trigger a huge RF key scan.
    expect(keys, [targetKey]);
    checkedKeys.addAll(keys.map(bytesToHex));
    return targetKey;
  }

  @override
  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async =>
      bytesToHex(key) == bytesToHex(targetKey);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final stable in [true, false]) {
    test('weak nested with stable distance $stable', () async {
      final communicator = WeakCardCommunicator(stable: stable);
      final app = ChameleonGUIState(SharedPreferencesProvider())
        ..communicator = communicator
        ..connector = WeakCardSerial()
        ..log = Logger(level: Level.off);
      final subject = MifareClassicRecovery(
        appState: app,
        update: () {},
        localizations: await AppLocalizations.delegate.load(const Locale('en')),
        mifareClassicType: MifareClassicType.m1k,
      );
      for (var sector = 1; sector < 16; sector++) {
        for (var type = 0; type < 2; type++) {
          subject.setKeyAsFound(sector, type, WeakCardCommunicator.knownKey);
        }
      }
      subject.checkMarks[40] = ChameleonKeyCheckmark.disabled;

      await subject.recoverKeys();

      expect(communicator.measurements, stable ? 1 : 5);
      expect(communicator.collectedLevels, [
        ...List.filled(stable ? 1 : 5, NTLevel.weak),
        if (!stable) NTLevel.hard,
      ]);
      expect(communicator.checkedKeys, [bytesToHex(communicator.targetKey)]);
      expect(subject.getSectorKey(0, 0), communicator.targetKey);
      expect(subject.allKeysExists, isTrue);
      expect(subject.state, isEmpty);
    });
  }
}
