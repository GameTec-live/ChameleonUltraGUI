import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';

import 'sl1_routes_test.dart' show ProfileRouteDevice;
import 'sl1_card_workflows_test.dart' show appFor, host;
import 'sl1_profile_test.dart' show fixture;

class CardAuthProbeDevice extends ProfileRouteDevice {
  bool rawSupported = true;
  int probeStatus = 0;
  List<int> challenge = [0x90, ...List.filled(16, 0xAB)];

  @override
  Future<bool> mf1Auth(int block, int keyType, Uint8List key) async => false;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    final result = (await super.sendCmd(cmd, data: data))!;
    if (cmd == ChameleonCommand.getDeviceCapabilities && rawSupported) {
      result.data = Uint8List.fromList([...result.data, 7, 0xDA]);
    } else if (cmd == ChameleonCommand.hf14ARawCommand) {
      result.status = probeStatus;
      result.data = Uint8List.fromList(challenge);
    }
    return result;
  }
}

void main() {
  testWidgets(
    'initial Classic scan detects CardAuth before a user AES key exists',
    (tester) async {
      final profile = fixture();
      profile.json['cardAuth'] = null;
      final device = CardAuthProbeDevice();
      final app = (await appFor(sl1ToCard(profile)))..communicator = device;
      MifareClassicInfo? info;
      await tester.pumpWidget(
        host(
          app,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                info = (await performMifareClassicScan(
                  device,
                  MifareClassicInfo(),
                  context,
                  () {},
                  override: TagType.mifareMini,
                  expectedIdentity: device.identity,
                )).$2;
              },
              child: const Text('Scan'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(info!.sl1CardAuthDetected, isTrue);
      expect(info!.recovery!.validKeys.every((key) => key.isEmpty), isTrue);
      expect(device.scans, greaterThanOrEqualTo(2));
    },
  );

  test('first detection sends no AES key and releases the field', () async {
    final device = CardAuthProbeDevice();
    expect(await device.detectSl1CardAuth(), isTrue);
    final index = device.calls.indexOf(ChameleonCommand.hf14ARawCommand.value);
    expect(device.payloads[index], [0xF4, 0, 100, 0, 24, 0x76, 4, 0x90]);
    expect(device.payloads[index][0] & 8, 0);
    expect(
      device.calls.where((c) => c == ChameleonCommand.hf14ARawCommand.value),
      hasLength(1),
    );
  });
  test(
    'ordinary, malformed and failed replies do not claim detection',
    () async {
      for (final response in [
        <int>[],
        [0x90],
        [0x90, ...List.filled(15, 0)],
        [0, ...List.filled(16, 0)],
      ]) {
        final device = CardAuthProbeDevice()..challenge = response;
        expect(await device.detectSl1CardAuth(), isFalse);
      }
      final failed = CardAuthProbeDevice()..probeStatus = 2;
      expect(await failed.detectSl1CardAuth(), isFalse);
      final legacy = CardAuthProbeDevice()..rawSupported = false;
      expect(await legacy.detectSl1CardAuth(), isFalse);
      expect(
        legacy.calls,
        isNot(contains(ChameleonCommand.hf14ARawCommand.value)),
      );
    },
  );
}
