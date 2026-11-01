import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

class TestSerial extends AbstractSerial {
  TestSerial(ConnectionType type) : super(log: Logger()) {
    connectionType = type;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCommunicator extends ChameleonCommunicator {
  TestCommunicator(this.respond) : super(Logger());
  final ChameleonMessage Function(ChameleonCommand, Uint8List?, Duration)
  respond;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async => respond(cmd, data, timeout);
}

ChameleonMessage reply(
  ChameleonCommand cmd,
  List<int> data, {
  int status = 0,
}) => ChameleonMessage(
  command: cmd.value,
  status: status,
  data: Uint8List.fromList(data),
);

Uint8List result(Map<int, List<int>> keys) {
  final data = Uint8List(490);
  for (final entry in keys.entries) {
    data[entry.key ~/ 8] |= 0x80 >> (entry.key % 8);
    data.setRange(10 + entry.key * 6, 16 + entry.key * 6, entry.value);
  }
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = Uint8List.fromList([1, 2, 3, 4, 5, 6]);

  test(
    'bridge sends mask and keys, scales timeout and parses first/last keys',
    () async {
      final mask = Uint8List(10);
      final communicator = TestCommunicator((cmd, data, timeout) {
        expect(cmd, ChameleonCommand.mf1CheckKeysOfSectors);
        expect(data, [...mask, ...key]);
        expect(timeout.inMilliseconds, 9100);
        return reply(cmd, result({0: key, 1: key, 79: key}), status: 1);
      });
      final found = await communicator.mf1CheckKeysOfSectors(mask, [key]);
      expect(found.keys, [0, 1, 79]);
      expect(found[79], key);
    },
  );

  test('bridge rejects malformed results and firmware errors', () async {
    for (final status in [0, 2]) {
      final communicator = TestCommunicator(
        (cmd, data, timeout) => reply(cmd, [0], status: status),
      );
      await expectLater(
        communicator.mf1CheckKeysOfSectors(Uint8List(10), [key]),
        throwsA(status == 0 ? isA<FormatException>() : isA<StateError>()),
      );
    }
  });

  Future<MifareClassicRecovery> recovery(
    TestCommunicator communicator, {
    ConnectionType type = ConnectionType.usb,
  }) async {
    final app = ChameleonGUIState(SharedPreferencesProvider())
      ..communicator = communicator
      ..connector = TestSerial(type)
      ..log = Logger();
    return MifareClassicRecovery(
      appState: app,
      update: () {},
      localizations: await AppLocalizations.delegate.load(const Locale('en')),
      mifareClassicType: MifareClassicType.m1k,
    );
  }

  for (final type in [ConnectionType.usb, ConnectionType.ble]) {
    test(
      'dictionary batches on $type preserve found/disabled keys and update masks',
      () async {
        final masks = <List<int>>[];
        final sizes = <int>[];
        final communicator = TestCommunicator((cmd, data, timeout) {
          if (cmd == ChameleonCommand.getDeviceCapabilities) {
            return reply(cmd, [0x07, 0xdc]); // 2012
          }
          expect(cmd, ChameleonCommand.mf1CheckKeysOfSectors);
          masks.add(data!.sublist(0, 10));
          sizes.add((data.length - 10) ~/ 6);
          return reply(cmd, result(masks.length == 1 ? {3: key} : {30: key}));
        });
        final subject = await recovery(communicator, type: type);
        subject.setKeyAsFound(0, 0, key);
        subject.checkMarks[40] = ChameleonKeyCheckmark.disabled;
        subject.selectedDictionary = Dictionary(
          keys: List.generate(
            65,
            (i) => Uint8List.fromList([0, 0, 0, 0, 0, i]),
          ),
        );
        await subject.checkKeys(skipDefaultDictionary: true);
        expect(sizes, type == ConnectionType.usb ? [64, 1] : [32, 32, 1]);
        expect(masks.first[0], 0xc0);
        expect(masks[1][0], 0xd0); // sector 1 B now found
        expect(
          masks.every((mask) => mask.skip(4).every((b) => b == 255)),
          isTrue,
        );
        expect(subject.getSectorKey(1, 1), key);
        expect(subject.getSectorKey(15, 0), key);
        expect(subject.getSectorState(0, 1), ChameleonKeyCheckmark.disabled);
        expect(
          subject.checkMarks,
          isNot(contains(ChameleonKeyCheckmark.checking)),
        );
        expect(subject.keyCheckProgress, isNull);
        expect(subject.allKeysExists, isFalse);
      },
    );
  }

  test(
    'recovered key recheck uses a batch starting at the requested sector',
    () async {
      final subject = await recovery(
        TestCommunicator((cmd, data, timeout) {
          if (cmd == ChameleonCommand.getDeviceCapabilities)
            return reply(cmd, [7, 220]);
          expect(cmd, ChameleonCommand.mf1CheckKeysOfSectors);
          expect(data!.take(2), [255, 0]);
          return reply(cmd, result({8: key, 31: key}));
        }),
      );
      await subject.recheckKey(key, 4);
      expect(subject.getSectorKey(4, 0), key);
      expect(subject.getSectorKey(15, 1), key);
      expect(subject.getSectorState(0, 0), ChameleonKeyCheckmark.none);
    },
  );

  test(
    'unsupported firmware uses block checks and individual key rechecks',
    () async {
      var blockChecks = 0;
      var rechecks = 0;
      final subject = await recovery(
        TestCommunicator((cmd, data, timeout) {
          if (cmd == ChameleonCommand.getDeviceCapabilities)
            return reply(cmd, []);
          if (cmd == ChameleonCommand.mf1CheckKeysOnBlock) {
            blockChecks++;
            return reply(cmd, [1, ...key]);
          }
          expect(cmd, ChameleonCommand.mf1CheckKey);
          rechecks++;
          return reply(cmd, []);
        }),
      );
      subject.selectedDictionary = Dictionary(keys: [key]);
      await subject.checkKeys(skipDefaultDictionary: true);
      expect(blockChecks, 1);
      expect(rechecks, 31);
      expect(subject.allKeysExists, isTrue);
    },
  );

  test('batch error clears checking marks and progress', () async {
    final subject = await recovery(
      TestCommunicator((cmd, data, timeout) {
        if (cmd == ChameleonCommand.getDeviceCapabilities)
          return reply(cmd, [7, 220]);
        throw StateError('disconnected');
      }),
    );
    subject.selectedDictionary = Dictionary(keys: [key]);
    await expectLater(subject.checkKeys(), throwsStateError);
    expect(subject.checkMarks, isNot(contains(ChameleonKeyCheckmark.checking)));
    expect(subject.keyCheckProgress, isNull);
  });
}
