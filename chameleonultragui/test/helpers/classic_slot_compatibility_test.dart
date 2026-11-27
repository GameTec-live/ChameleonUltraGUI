import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';

import 'sl1_card_workflows_test.dart'
    show appFor, host, SlotRouteProbe, SlotRouteProbeState;
import 'sl1_profile_test.dart' show fixture;
import 'sl1_routes_test.dart' show ProfileRouteDevice;

class LegacyProfileDevice extends ProfileRouteDevice {
  final bool partial;
  LegacyProfileDevice(this.partial) {
    supported = partial;
  }

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    final response = (await super.sendCmd(cmd, data: data))!;
    if (partial && cmd == ChameleonCommand.getDeviceCapabilities) {
      response.data = response.data.sublist(0, response.data.length - 2);
    }
    return response;
  }
}

Future<(bool, int)> upload(
  WidgetTester tester,
  ProfileRouteDevice device,
  Sl1Profile profile,
) async {
  final card = sl1ToCard(profile);
  final app = (await appFor(card))..communicator = device;
  final key = GlobalKey<SlotRouteProbeState>();
  await tester.pumpWidget(host(app, SlotRouteProbe(key: key)));
  var closed = 0;
  final pending = key.currentState!.onTap(
    card,
    (_, _) => closed++,
    await AppLocalizations.delegate.load(const Locale('en')),
  );
  await tester.pumpAndSettle();
  final failed = find.text('Profile upload stopped').evaluate().isNotEmpty;
  if (failed) {
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  }
  await pending;
  return (failed, closed);
}

void main() {
  for (final partial in [false, true]) {
    testWidgets(
      'Classic-only upload retains the legacy slot route, partial API=$partial',
      (tester) async {
        final device = LegacyProfileDevice(partial);
        final profile = fixture();
        profile.json['cardAuth'] = null;
        profile.json['classic']['blocks'][3]['data'] =
            '${'??' * 6}FF078069${'??' * 6}';
        final (failed, closed) = await upload(tester, device, profile);
        expect(failed, isFalse);
        expect(closed, 1);
        final written = <int, List<int>>{};
        for (var i = 0; i < device.calls.length; i++) {
          if (device.calls[i] != ChameleonCommand.mf1LoadBlockData.value) {
            continue;
          }
          final payload = device.payloads[i];
          for (var offset = 1; offset < payload.length; offset += 16) {
            written[payload[0] + (offset - 1) ~/ 16] = payload.sublist(
              offset,
              offset + 16,
            );
          }
        }
        final expected = profile.image();
        expect(written.length, expected.length);
        for (var block = 0; block < expected.length; block++) {
          expect(written[block], expected[block]);
        }
        expect(device.calls.where((c) => c >= 4045 && c <= 4051), isEmpty);
      },
    );
  }

  for (final incomplete in [false, true]) {
    testWidgets(
      'legacy fallback cannot drop CardAuth or unknown bytes, incomplete=$incomplete',
      (tester) async {
        final device = LegacyProfileDevice(false);
        final profile = fixture();
        if (incomplete) {
          profile.json['cardAuth'] = null;
          profile.json['classic']['blocks'][1]['data'] = '??' * 16;
          profile.json['classic']['blocks'][1]['status'] = 'unread';
        }
        final (failed, _) = await upload(tester, device, profile);
        expect(failed, isTrue);
        expect(
          device.calls,
          isNot(contains(ChameleonCommand.changeDeviceMode.value)),
        );
        expect(
          device.calls,
          isNot(contains(ChameleonCommand.setSlotDataDefault.value)),
        );
        expect(
          device.calls,
          isNot(contains(ChameleonCommand.mf1LoadBlockData.value)),
        );
      },
    );
  }
}
