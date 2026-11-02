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

class StaticCardSerial extends Fake implements AbstractSerial {
  @override
  ConnectionType get connectionType => ConnectionType.usb;
}

class StaticCardCommunicator extends ChameleonCommunicator {
  StaticCardCommunicator(this.sourceKeyType) : super(Logger(level: Level.off));

  final int sourceKeyType;
  final checkedTypes = <int>[];
  static final knownKey = hexToBytes('FFFFFFFFFFFF');
  static final targetKeys = [
    hexToBytes('112233445566'),
    hexToBytes('A0A1A2A3A4A5'),
  ];

  @override
  Future<NTLevel> getMf1NTLevel() async => NTLevel.static;

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
    // No backdoor; recover sector 0 using an already-known sector 15 key.
    return ChameleonMessage(command: cmd.value, status: 0, data: Uint8List(0));
  }

  @override
  Future<NTDistance> getMf1NTDistance(
    int block,
    int keyType,
    Uint8List keyKnown,
  ) async {
    expect((block, keyType), (63, sourceKeyType));
    expect(keyKnown, knownKey);
    return NTDistance(uid: 0x11223344, distance: 0);
  }

  @override
  Future<NestedNonces> getMf1NestedNonces(
    int block,
    int keyType,
    Uint8List knownKey,
    int targetBlock,
    int targetKeyType, {
    NTLevel level = NTLevel.weak,
    bool slow = false,
  }) async {
    if (level == NTLevel.hard) {
      // Distinct first bytes rule out the static-encrypted/backdoor path.
      return NestedNonces(
        nonces: [NestedNonce(nt: 0x11223344, ntEnc: 0x55667788, parity: 0)],
      );
    }
    expect(level, NTLevel.static);
    expect((block, keyType, targetBlock), (63, sourceKeyType, 3));
    expect(knownKey, StaticCardCommunicator.knownKey);
    // Synthetic gen-2 captures for the keys above. A uses offsets 160/320;
    // B uses 161/321, independently of the known key used to collect them.
    final encrypted = targetKeyType == 0x60
        ? [997011713, 499090052]
        : [3478540890, 3057512422];
    return NestedNonces(
      nonces: [
        for (final ntEnc in encrypted)
          NestedNonce(nt: 0x009080a2, ntEnc: ntEnc, parity: 0),
      ],
    );
  }

  @override
  Future<Uint8List?> mf1AuthMultipleKeys(
    int block,
    int keyType,
    List<Uint8List> keys,
  ) async {
    expect(block, 3);
    final expected = targetKeys[keyType - 0x60];
    // A correct capture produces one key, not a huge RF candidate scan.
    expect(keys.map(bytesToHex), [bytesToHex(expected)]);
    checkedTypes.add(keyType);
    return expected;
  }

  @override
  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async =>
      bytesToHex(key) == bytesToHex(targetKeys[keyType - 0x60]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sourceType in [0x60, 0x61]) {
    test(
      'static nested targets A then B using known key type $sourceType',
      () async {
        final communicator = StaticCardCommunicator(sourceType);
        final app = ChameleonGUIState(SharedPreferencesProvider())
          ..communicator = communicator
          ..connector = StaticCardSerial()
          ..log = Logger(level: Level.off);
        final subject = MifareClassicRecovery(
          appState: app,
          update: () {},
          localizations: await AppLocalizations.delegate.load(
            const Locale('en'),
          ),
          mifareClassicType: MifareClassicType.m1k,
        );
        for (var sector = 1; sector < 16; sector++) {
          for (var type = 0; type < 2; type++) {
            subject.setKeyAsFound(
              sector,
              type,
              StaticCardCommunicator.knownKey,
            );
          }
        }
        if (sourceType == 0x61) {
          subject.checkMarks[15] = ChameleonKeyCheckmark.disabled;
        }

        await subject.recoverKeys();

        expect(communicator.checkedTypes, [0x60, 0x61]);
        expect(
          subject.getSectorKey(0, 0),
          StaticCardCommunicator.targetKeys[0],
        );
        expect(
          subject.getSectorKey(0, 1),
          StaticCardCommunicator.targetKeys[1],
        );
        expect(subject.allKeysExists, isTrue);
      },
    );
  }
}
