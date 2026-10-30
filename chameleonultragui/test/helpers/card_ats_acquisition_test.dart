import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/helpers/definitions.dart';

import 'sl1_routes_test.dart' show ProfileRouteDevice, acquisition;

class AtsReadDevice extends ProfileRouteDevice {
  List<int> config = [255, 0, 0, 2];
  final writes = <List<int>>[];
  bool exposeAts = true;
  bool configSupported = true;
  bool failForcedScan = false;
  bool failRestore = false;

  @override
  CardData get identity => CardData(
    uid: Uint8List.fromList([1, 2, 3, 4]),
    atqa: Uint8List.fromList([0x12, 0x34]),
    sak: 8,
    ats: Uint8List.fromList(config[3] == 1 && exposeAts ? [2, 0x75] : []),
  );

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    final response = (await super.sendCmd(cmd, data: data))!;
    if (cmd == ChameleonCommand.getDeviceCapabilities && configSupported) {
      response.data = Uint8List.fromList([...response.data, 8, 0x98, 8, 0x99]);
    } else if (cmd == ChameleonCommand.hf14aGetConfig) {
      response.data = Uint8List.fromList(config);
    } else if (cmd == ChameleonCommand.hf14aSetConfig) {
      writes.add(data!.toList());
      if (failRestore && data[3] == 2) {
        response.status = 0x66;
      } else {
        config = data.toList();
      }
    } else if (cmd == ChameleonCommand.scan14ATag &&
        config[3] == 1 &&
        failForcedScan) {
      throw StateError('Synthetic forced scan failure');
    }
    return response;
  }
}

class PausedAtsReadDevice extends AtsReadDevice {
  final forcedScanStarted = Completer<void>();
  final releaseForcedScan = Completer<void>();
  final scanSettings = <int>[];
  bool _paused = false;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    if (cmd == ChameleonCommand.scan14ATag) {
      scanSettings.add(config[3]);
      if (config[3] == 1 && !_paused) {
        _paused = true;
        forcedScanStarted.complete();
        await releaseForcedScan.future;
      }
    }
    return super.sendCmd(cmd, data: data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (withAts, failFirst) in [
    (true, false),
    (false, false),
    (false, true),
  ]) {
    test(
      'queued scan waits for ATS settings restoration, ATS=$withAts failure=$failFirst',
      () async {
        final device = PausedAtsReadDevice()..failForcedScan = failFirst;
        final selected = device.identity;
        final first = device.scan14443aTagWithAts().then<Object?>(
          (card) => card,
          onError: (Object error) => error,
        );
        await device.forcedScanStarted.future;
        final next = (withAts
                ? device.scan14443aTagWithAts(selected: selected)
                : device.scan14443aTag())
            .then<Object?>((card) => card, onError: (Object error) => error);
        await Future<void>.delayed(Duration.zero);
        final settingsWhileBlocked = device.scanSettings.toList();
        device.releaseForcedScan.complete();
        final firstResult = await first;
        final nextResult = await next;

        expect(settingsWhileBlocked, [2, 1]);
        expect(firstResult, failFirst ? isA<StateError>() : isA<CardData>());
        expect(nextResult, isA<CardData>());
        expect((nextResult as CardData).ats, withAts ? [2, 0x75] : isEmpty);
        expect(device.config, [255, 0, 0, 2]);
        expect(device.writes, [
          [255, 0, 0, 1],
          [255, 0, 0, 2],
          if (withAts) ...[
            [255, 0, 0, 1],
            [255, 0, 0, 2],
          ],
        ]);
      },
    );
  }

  test(
    'Classic-compatible SAK acquires ATS and retains it through bound reads',
    () async {
      final device = AtsReadDevice();
      final (recovery, card) = await acquisition(device);
      final selected = await device.scan14443aTagWithAts();
      expect(selected!.ats, [2, 0x75]);
      expect(device.config, [255, 0, 0, 2]);
      expect(device.writes, [
        [255, 0, 0, 1],
        [255, 0, 0, 2],
      ]);
      recovery.bindIdentity(selected);
      card.ats = selected.ats;
      await recovery.dumpData();
      expect(recovery.profileFor(card).json['hf14a']['ats'], '0275');
      expect(device.config, [255, 0, 0, 2]);
    },
  );

  test('already acquired ATS does not change reader configuration', () async {
    final device = AtsReadDevice()..config[3] = 1;
    expect((await device.scan14443aTagWithAts())!.ats, [2, 0x75]);
    expect(device.writes, isEmpty);
  });

  test('ordinary Classic and legacy firmware retain an empty ATS', () async {
    final ordinary = AtsReadDevice()..exposeAts = false;
    expect((await ordinary.scan14443aTagWithAts())!.ats, isEmpty);
    expect(ordinary.config, [255, 0, 0, 2]);
    final legacy = AtsReadDevice()..configSupported = false;
    expect((await legacy.scan14443aTagWithAts())!.ats, isEmpty);
    expect(legacy.writes, isEmpty);
  });

  test('card replacement is rejected and configuration restored', () async {
    final device = AtsReadDevice()..changeAtScan = 2;
    await expectLater(device.scan14443aTagWithAts(), throwsStateError);
    expect(device.config, [255, 0, 0, 2]);
  });

  for (final failRestore in [false, true]) {
    test(
      'scan failure restores settings or reports both failures, restore=$failRestore',
      () async {
        final device = AtsReadDevice()
          ..failForcedScan = true
          ..failRestore = failRestore;
        await expectLater(
          device.scan14443aTagWithAts(),
          throwsA(
            isA<StateError>().having(
              (e) => e.toString(),
              'failure detail',
              allOf([
                contains('Synthetic forced scan failure'),
                if (failRestore) contains('Could not restore'),
              ]),
            ),
          ),
        );
        expect(device.writes.last, [255, 0, 0, 2]);
        if (!failRestore) expect(device.config, [255, 0, 0, 2]);
      },
    );
  }
}
