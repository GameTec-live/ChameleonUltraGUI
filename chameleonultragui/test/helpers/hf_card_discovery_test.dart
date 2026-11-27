import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';

import 'card_ats_acquisition_test.dart' show AtsReadDevice;
import 'sl1_card_workflows_test.dart' show appFor, host;
import 'sl1_profile_test.dart' show fixture;

class DiscoveryDevice extends AtsReadDevice {
  bool cardAuth = false;
  bool probeFails = false;
  bool removeOnFallback = false;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    final response = (await super.sendCmd(cmd, data: data))!;
    if (cmd == ChameleonCommand.scan14ATag && removeOnFallback && scans >= 3) {
      response.status = 1;
      response.data = Uint8List(0);
    } else if (cmd == ChameleonCommand.scan14ATag &&
        config[3] == 1 &&
        !exposeAts) {
      // The CU can reject forced RATS for a card that scans normally.
      response.status = 0x08;
      response.data = Uint8List(0);
    } else if (cmd == ChameleonCommand.getDeviceCapabilities) {
      response.data = Uint8List.fromList([...response.data, 7, 0xDA]);
    } else if (cmd == ChameleonCommand.mf1SupportDetect) {
      response.status = 0;
    } else if (cmd == ChameleonCommand.mf1NTLevelDetect) {
      response.status = 0;
      response.data = Uint8List.fromList([2]);
    } else if (cmd == ChameleonCommand.mf1CheckKey) {
      response.status = 6;
    } else if (cmd == ChameleonCommand.hf14ARawCommand) {
      final request = data!.sublist(5);
      response.status = 0;
      if (request[0] == 0x76) {
        if (probeFails) throw StateError('Synthetic optional probe failure');
        response.data = Uint8List.fromList(
          cardAuth ? [0x90, ...List.filled(16, 0xAB)] : [],
        );
      } else {
        response.data = Uint8List.fromList(
          request[0] == 0x60 && request[1] == 63 ? [1, 2, 3, 4] : [],
        );
      }
    }
    return response;
  }
}

class SlowDiscoveryDevice extends DiscoveryDevice {
  final firstScan = Completer<void>();
  int scanStarts = 0;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    if (cmd == ChameleonCommand.scan14ATag) {
      scanStarts++;
      if (scanStarts == 1) await firstScan.future;
    }
    return super.sendCmd(cmd, data: data);
  }
}

class DiscoveryPage extends ReadCardPage {
  const DiscoveryPage({super.key});

  @override
  DiscoveryPageState createState() => DiscoveryPageState();
}

class DiscoveryPageState extends ReadCardPageState {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

Future<(HFCardInfo, MifareClassicInfo)> discover(
  WidgetTester tester,
  DiscoveryDevice device,
) async {
  final app = (await appFor(sl1ToCard(fixture())))..communicator = device;
  HFCardInfo? hf;
  MifareClassicInfo? classic;
  await tester.pumpWidget(
    host(
      app,
      Builder(
        builder: (context) {
          return TextButton(
            onPressed: () async {
              final result = await readHFInfo(context, () {});
              hf = result.$1;
              classic = result.$2;
            },
            child: const Text('Read HF'),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Read HF'));
  await tester.pumpAndSettle();
  return (hf!, classic!);
}

void main() {
  testWidgets('continuous scanning does not overlap a slow initial read', (
    tester,
  ) async {
    final device = SlowDiscoveryDevice()..cardAuth = true;
    final app = (await appFor(sl1ToCard(fixture())))..communicator = device;
    final key = GlobalKey<DiscoveryPageState>();
    await tester.pumpWidget(host(app, DiscoveryPage(key: key)));
    final reading = key.currentState!.startContinuousHFScan();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final startedBeforeCompletion = device.scanStarts;
    key.currentState!.stopContinuousHFScan();
    device.firstScan.complete();
    await tester.pumpAndSettle();
    await reading;
    expect(startedBeforeCompletion, 1);
    expect(key.currentState!.hfInfo.uid, isEmpty);
  });

  for (final disposed in [false, true]) {
    testWidgets('slow HF read completes safely, disposed=$disposed', (
      tester,
    ) async {
      final device = SlowDiscoveryDevice()..cardAuth = true;
      final app = (await appFor(sl1ToCard(fixture())))..communicator = device;
      final key = GlobalKey<DiscoveryPageState>();
      await tester.pumpWidget(host(app, DiscoveryPage(key: key)));
      final reading = key.currentState!.startContinuousHFScan();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      if (disposed) await tester.pumpWidget(const SizedBox());
      device.firstScan.complete();
      await tester.pumpAndSettle();
      await reading;
      if (!disposed) {
        expect(key.currentState!.hfInfo.cardExist, isTrue);
        expect(key.currentState!.hfInfo.ats, '02 75');
        expect(key.currentState!.mfcInfo.sl1CardAuthDetected, isTrue);
        expect(key.currentState!.isContinuousHFScan, isFalse);
      }
    });
  }

  for (final probeFails in [false, true]) {
    testWidgets(
      'ordinary Classic discovery survives rejected RATS, probe failure=$probeFails',
      (tester) async {
        final device = DiscoveryDevice()
          ..exposeAts = false
          ..probeFails = probeFails;
        final (hf, classic) = await discover(tester, device);
        expect(hf.cardExist, isTrue);
        expect(hf.type, TagType.mifare1K);
        expect(classic.sl1CardAuthDetected, isFalse);
        expect(classic.state, MifareClassicState.checkKeys);
        expect(device.config, [255, 0, 0, 2]);
        expect(device.writes.last, [255, 0, 0, 2]);
      },
    );
  }

  testWidgets('full initial SL1 discovery detects support and acquires ATS', (
    tester,
  ) async {
    final device = DiscoveryDevice()..cardAuth = true;
    final (hf, classic) = await discover(tester, device);
    expect(hf.cardExist, isTrue);
    expect(hf.type, TagType.mifare1K);
    expect(hf.ats, '02 75');
    expect(classic.sl1CardAuthDetected, isTrue);
    expect(classic.recovery!.validKeys.every((key) => key.isEmpty), isTrue);
    expect(device.config, [255, 0, 0, 2]);
  });

  testWidgets(
    'manual CardAuth fallback retains ATS after an inconclusive probe',
    (tester) async {
      final device = DiscoveryDevice()..probeFails = true;
      final (hf, classic) = await discover(tester, device);
      expect(hf.cardExist, isTrue);
      expect(hf.ats, '02 75');
      expect(classic.sl1CardAuthDetected, isFalse);
      expect(device.config, [255, 0, 0, 2]);
    },
  );

  testWidgets('a changed card is still rejected during initial discovery', (
    tester,
  ) async {
    final device = DiscoveryDevice()..changeAtScan = 2;
    final (hf, _) = await discover(tester, device);
    expect(hf.cardExist, isFalse);
  });

  for (final removed in [false, true]) {
    testWidgets(
      'normal fallback rejects a replaced or missing card, removed=$removed',
      (tester) async {
        final device = DiscoveryDevice()
          ..exposeAts = false
          ..changeAtScan = removed ? null : 3
          ..removeOnFallback = removed;
        final (hf, _) = await discover(tester, device);
        expect(hf.cardExist, isFalse);
        expect(device.config, [255, 0, 0, 2]);
      },
    );
  }

  testWidgets(
    'SL1 discovery does not hide a reader configuration restore failure',
    (tester) async {
      final device = DiscoveryDevice()
        ..cardAuth = true
        ..failRestore = true;
      final (hf, _) = await discover(tester, device);
      expect(hf.cardExist, isFalse);
      expect(device.writes.last, [255, 0, 0, 2]);
    },
  );
}
