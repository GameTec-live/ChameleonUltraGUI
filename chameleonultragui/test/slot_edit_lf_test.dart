import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/edit.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _getters = {
  ChameleonCommand.getEM410XemulatorID: TagType.em410X,
  ChameleonCommand.getHIDProxEmulatorID: TagType.hidProx,
  ChameleonCommand.getVikingEmulatorID: TagType.viking,
  ChameleonCommand.getJablotronEmulatorID: TagType.jablotron,
};

const _setters = {
  ChameleonCommand.setEM410XemulatorID: TagType.em410X,
  ChameleonCommand.setHIDProxEmulatorID: TagType.hidProx,
  ChameleonCommand.setVikingEmulatorID: TagType.viking,
  ChameleonCommand.setJablotronEmulatorID: TagType.jablotron,
};

const _defaults = {
  TagType.em410X: [0xDE, 0xAD, 0xBE, 0xEF, 0x88],
  TagType.hidProx: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  TagType.viking: [0xDE, 0xAD, 0xBE, 0xEF],
  TagType.jablotron: [0, 0, 0, 0, 0],
};

/// Behaves like the firmware's LF slot: an ID can only be read back for the
/// slot's current LF type, otherwise the reply is a parameter error with no
/// data (app_cmd.c, e.g. cmd_processor_hidprox_get_emu_id).
class _LfSlotDevice extends ChameleonCommunicator {
  _LfSlotDevice(this.lfType, this.ids) : super(Logger(level: Level.off));

  TagType lfType;
  final Map<TagType, List<int>> ids;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    var status = 0x68;
    var response = <int>[];
    if (cmd == ChameleonCommand.setSlotTagType) {
      lfType = TagType.values.firstWhere(
        (t) => t.value == (data![1] << 8 | data[2]),
      );
    } else if (cmd == ChameleonCommand.setSlotDataDefault) {
      ids[lfType] = [..._defaults[lfType]!];
    } else if (_setters.containsKey(cmd)) {
      ids[_setters[cmd]!] = data!.toList();
    } else if (_getters.containsKey(cmd)) {
      if (_getters[cmd] == lfType && ids.containsKey(lfType)) {
        response = ids[lfType]!;
      } else {
        status = 0x60;
      }
    }
    return ChameleonMessage(
      command: cmd.value,
      status: status,
      data: Uint8List.fromList(response),
    );
  }
}

Future<void> _openSlotEdit(
  WidgetTester tester,
  _LfSlotDevice device,
  TagType slotType,
) async {
  SharedPreferences.setMockInitialValues({});
  await SharedPreferencesProvider().load();
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: ChameleonGUIState(SharedPreferencesProvider())
        ..communicator = device,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => SlotEditMenu(
                name: 'Door',
                isEnabled: true,
                slotType: slotType,
                frequency: TagFrequency.lf,
                slot: 0,
                update: (_, _, _) {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), text);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  expect(find.byType(SlotEditMenu), findsNothing);
}

void main() {
  testWidgets('saving a Viking slot sends the new ID', (tester) async {
    final device = _LfSlotDevice(TagType.viking, {
      TagType.viking: [1, 2, 3, 4],
    });
    await _openSlotEdit(tester, device, TagType.viking);
    expect(find.text('01 02 03 04'), findsOneWidget);

    await _enter(tester, 'UID', '12 34 56 78');
    await _save(tester);

    expect(device.ids[TagType.viking], [0x12, 0x34, 0x56, 0x78]);
  });

  testWidgets(
    'switching a slot to HID Prox with the default format sends the ID',
    (tester) async {
      final device = _LfSlotDevice(TagType.em410X, {
        TagType.em410X: [0xDE, 0xAD, 0xBE, 0xEF, 0x88],
      });
      await _openSlotEdit(tester, device, TagType.em410X);

      await tester.tap(find.byType(DropdownButton<TagType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HID Prox').last);
      await tester.pumpAndSettle();
      expect(find.text('HID H10301 26-bit'), findsOneWidget);

      await _enter(tester, 'UID', '00 00 00 30 39');
      await _enter(tester, 'Facility Code', '123');
      await _enter(tester, 'Issue Level', '0');
      await _enter(tester, 'OEM', '0');
      await _save(tester);

      expect(device.lfType, TagType.hidProx);
      expect(device.ids[TagType.hidProx], [
        1, // H10301
        0, 0, 0, 123, // facility code
        0, 0, 0, 0x30, 0x39, // card number 12345
        0, // issue level
        0, 0, // OEM
      ]);
    },
  );

  testWidgets('editing an existing HID Prox slot keeps its format', (
    tester,
  ) async {
    final device = _LfSlotDevice(TagType.hidProx, {
      TagType.hidProx: [2, 0, 0, 0, 5, 0, 0, 0, 0, 7, 0, 0, 0],
    });
    await _openSlotEdit(tester, device, TagType.hidProx);
    expect(find.text('Indala 26-bit'), findsOneWidget);

    await _enter(tester, 'Facility Code', '6');
    await _save(tester);

    expect(device.ids[TagType.hidProx], [
      2,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      0,
      7,
      0,
      0,
      0,
    ]);
  });

  testWidgets('saving a Jablotron slot sends the new ID', (tester) async {
    final device = _LfSlotDevice(TagType.jablotron, {
      TagType.jablotron: [0, 0x11, 0x22, 0x33, 0x44],
    });
    await _openSlotEdit(tester, device, TagType.jablotron);

    await _enter(tester, 'UID', '00 12 34 56 78');
    await _save(tester);

    expect(device.ids[TagType.jablotron], [0, 0x12, 0x34, 0x56, 0x78]);
  });
}
