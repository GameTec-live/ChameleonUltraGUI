import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/edit.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';

import 'sl1_card_workflows_test.dart' show appFor, host;
import 'sl1_profile_test.dart' show fixture;
import 'sl1_routes_test.dart' show ProfileRouteDevice;

class SlotEditProbe extends SlotEditMenu {
  const SlotEditProbe({super.key})
    : super(
        name: 'Original',
        isEnabled: true,
        slotType: TagType.mifareMini,
        frequency: TagFrequency.hf,
        slot: 1,
        update: _changed,
      );
  static void _changed(String name, TagFrequency frequency, TagType type) {}
  @override
  SlotEditProbeState createState() => SlotEditProbeState();
}

class SlotEditProbeState extends SlotEditMenuState {
  @override
  Widget build(BuildContext context) => const Scaffold();
}

void main() {
  for (final identityChange in [false, true]) {
    testWidgets(
      'slot save preserves CardAuth unless identity changes: $identityChange',
      (tester) async {
        final device = ProfileRouteDevice();
        final app = (await appFor(sl1ToCard(fixture())))..communicator = device;
        final key = GlobalKey<SlotEditProbeState>();
        await tester.pumpWidget(host(app, SlotEditProbe(key: key)));
        final state = key.currentState!;
        final original = device.identity;
        state.originalAntiCollision = original;
        state.uidController.text = identityChange
            ? '11 22 33 44'
            : bytesToHexSpace(original.uid);
        state.atqaController.text = bytesToHexSpace(original.atqa);
        state.sakController.text = '09';
        state.atsController.text = bytesToHexSpace(original.ats);
        state.nameController.text = 'Renamed';
        await state.save();
        expect(
          device.calls.where(
          (c) => c == ChameleonCommand.mf1SetAntiCollision.value,
          ),
          hasLength(identityChange ? 1 : 0),
        );
        expect(device.calls, contains(ChameleonCommand.setSlotTagNick.value));
      },
    );
  }
}
