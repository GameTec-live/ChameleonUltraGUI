import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';

import 'card_ats_acquisition_test.dart' show AtsReadDevice;
import 'sl1_card_workflows_test.dart'
    show appFor, host, ReadRouteProbe, ReadRouteProbeState;
import 'sl1_profile_test.dart' show fixture;

void main() {
  testWidgets('type override retains ATS acquired with forced RATS', (
    tester,
  ) async {
    final device = AtsReadDevice();
    final app = (await appFor(sl1ToCard(fixture())))..communicator = device;
    final key = GlobalKey<ReadRouteProbeState>();
    await tester.pumpWidget(host(app, ReadRouteProbe(key: key)));
    final state = key.currentState!;
    state.hfInfo = HFCardInfo(
      uid: '01020304',
      sak: '08',
      atqa: '12 34',
      ats: '02 75',
      type: TagType.mifare1K,
    );
    final pending = state.applyTypeOverride(TagType.mifare2K);
    await tester.pumpAndSettle();
    if (find.text('Card type change failed').evaluate().isNotEmpty) {
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
    expect(await pending, isTrue);
    expect(state.hfInfo.type, TagType.mifare2K);
    expect(state.hfInfo.ats, '02 75');
    expect(device.config, [255, 0, 0, 2]);
  });
}
