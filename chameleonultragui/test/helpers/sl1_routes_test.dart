import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/helpers/card_file_import.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'sl1_profile_test.dart' show fixture;

class ProfileRouteDevice extends ChameleonCommunicator {
  ProfileRouteDevice() : super(Logger(level: Level.off));
  final calls = <int>[];
  final payloads = <List<int>>[];
  bool reader = true;
  bool supported = true;
  int modeStatus = 0x68;
  int scans = 0;
  int? changeAtScan;
  bool failA = false;
  bool failB = false;
  CardData get identity => CardData(
    uid: Uint8List.fromList([1, 2, 3, 4]),
    atqa: Uint8List.fromList([0x12, 0x34]),
    sak: 9,
    ats: Sl1Profile.bytes('0275'),
  );
  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    calls.add(cmd.value);
    payloads.add(data?.toList() ?? []);
    var status = 0x68;
    var result = <int>[];
    if (cmd == ChameleonCommand.getDeviceCapabilities) {
      result = [
        if (supported)
          for (var c = 4045; c <= 4051; c++) ...[c >> 8, c & 255],
      ];
    } else if (cmd == ChameleonCommand.getDeviceMode) {
      result = [reader ? 1 : 0];
    } else if (cmd == ChameleonCommand.changeDeviceMode) {
      status = modeStatus;
      if (status == 0x68) reader = data![0] == 1;
    } else if (cmd == ChameleonCommand.scan14ATag) {
      scans++;
      final card = identity;
      final uid = card.uid.toList();
      if (changeAtScan != null && scans >= changeAtScan!) uid[0] = 0x77;
      status = 0;
      result = [
        4,
        ...uid,
        ...card.atqa.reversed,
        card.sak,
        card.ats.length,
        ...card.ats,
      ];
    } else if (cmd == ChameleonCommand.mf1ReadBlock) {
      final isA = data![0] == 0x60;
      status = (isA ? failA : failB) ? 6 : 0;
      if (status == 0) {
        result = data[1] % 4 == 3
            ? Sl1Profile.bytes('000000000000FF078069FFFFFFFFFFFF')
            : List.filled(16, 0);
      }
    } else if (cmd == ChameleonCommand.sl1Status) {
      result = [1, data![1], ...List.filled(12, 0)];
    }
    return ChameleonMessage(
      command: cmd.value,
      status: status,
      data: Uint8List.fromList(result),
    );
  }
}

Future<(MifareClassicRecovery, CardSave)> acquisition(
  ProfileRouteDevice device,
) async {
  final app = ChameleonGUIState(SharedPreferencesProvider())
    ..communicator = device
    ..log = Logger(level: Level.off);
  final r = MifareClassicRecovery(
    appState: app,
    update: () {},
    localizations: await AppLocalizations.delegate.load(const Locale('en')),
    mifareClassicType: MifareClassicType.mini,
  );
  r.bindIdentity(device.identity);
  for (var s = 0; s < 5; s++) {
    for (var k = 0; k < 2; k++) {
      r.setKeyAsFound(s, k, Uint8List.fromList(List.filled(6, 255)));
    }
  }
  final scanned = await device.scan14443aTag();
  final card = CardSave(
    uid: Sl1Profile.encodeBytes(scanned!.uid),
    name: 'Synthetic yellow',
    tag: TagType.mifareMini,
    sak: scanned.sak,
    atqa: scanned.atqa,
    ats: scanned.ats,
  );
  return (r, card);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'scan, recovery save, export and BEGIN preserve asymmetric wire ATQA',
    () async {
      final device = ProfileRouteDevice();
      final (r, card) = await acquisition(device);
      await r.dumpData();
      card.data = r.cardData;
      card.sl1Profile = r.profileFor(card);
      expect(card.atqa, [0x12, 0x34]);
      expect(card.sl1Profile!.json['hf14a']['atqa'], '3412');
      final imported = importCardText(
        exportSl1Card(card),
        filename: 'different-name.json',
      );
      expect(imported.name, 'Synthetic yellow');
      expect(imported.atqa, card.atqa);
      await device.sl1Uploader.upload(imported.sl1Profile!, 3);
      final begin = device.calls.indexOf(4046);
      final mode = device.calls.indexOf(
        ChameleonCommand.changeDeviceMode.value,
      );
      expect(mode, lessThan(begin));
      expect(device.reader, isFalse);
      expect(device.payloads[begin].sublist(12, 14), [0x34, 0x12]);
    },
  );
  test('unsupported/incomplete input never changes mode; controls exit reader mode', () async {
    final device = ProfileRouteDevice()..supported = false;
    await expectLater(
      device.sl1Uploader.upload(fixture(), 3),
      throwsUnsupportedError,
    );
    expect(device.calls, isNot(contains(ChameleonCommand.getDeviceMode.value)));
    final p = fixture();
    p.json['classic']['blocks'][0]['data'] = '??' * 16;
    device.calls.clear();
    await expectLater(device.sl1Uploader.upload(p, 3), throwsFormatException);
    expect(device.calls, isEmpty);
    device.supported = true;
    for (final action in [
      () => device.sl1Uploader.clear(3),
      () => device.sl1Uploader.setEnabled(3, true),
      () => device.sl1Uploader.setEnabled(3, false),
    ]) {
      device.reader = true;
      device.calls.clear();
      await action();
      expect(
        device.calls.indexOf(ChameleonCommand.changeDeviceMode.value),
        lessThan(device.calls.length - 1),
      );
      expect(device.reader, isFalse);
    }
    device.reader = true;
    device.modeStatus = 0x66;
    device.calls.clear();
    await expectLater(
      device.sl1Uploader.upload(fixture(), 3),
      throwsStateError,
    );
    expect(device.calls, isNot(contains(4046)));
  });
  test(
    'changed initial identity and mid-acquisition swap reject saving',
    () async {
      for (final scan in [2, 5]) {
        final device = ProfileRouteDevice()..changeAtScan = scan;
        final (r, card) = await acquisition(device);
        await expectLater(r.dumpData(), throwsStateError);
        expect(() => r.profileFor(card), throwsStateError);
      }
    },
  );
  test(
    'real recovery preserves A failure/B success and all-fail raw statuses',
    () async {
      for (final allFail in [false, true]) {
        final device = ProfileRouteDevice()
          ..failA = true
          ..failB = allFail;
        final (r, card) = await acquisition(device);
        await r.dumpData();
        card.data = r.cardData;
        final profile = Sl1Profile.parse(r.profileFor(card).export());
        final block = profile.json['classic']['blocks'][0];
        expect(block['errors'][0]['key'], 'A');
        expect(block['errors'][0]['status'], 6);
        expect(block['status'], allFail ? 'error' : 'read');
        expect(block['data'], allFail ? '??' * 16 : '00' * 16);
        expect(block['key'], allFail ? null : 'B');
        expect(profile.json['classic']['keys'][0]['a']['status'], 'provided');
        if (allFail) {
          expect(block['errors'][1]['status'], 6);
          expect(r.cardData[0], isEmpty);
        }
      }
    },
  );
  test('actual import dispatcher rejects duplicates/malformed structured binary sizes', () {
    final source = fixture().export();
    for (final field in ['"version"', r'"versi\u006fn"']) {
      final bad = source.replaceFirst(
        '"version": 1',
        '"version": 1, $field: 1',
      );
      expect(
        () => importCardText(bad, filename: 'bad.json'),
        throwsFormatException,
      );
    }
    final bad = Uint8List.fromList(
      utf8.encode('{"format":"chameleon-sl1-profile"'.padRight(1024, ' ')),
    );
    expect(isStructuredCardFile(bad), isTrue);
    expect(
      () => importCardText(utf8.decode(bad), filename: 'bad.bin'),
      throwsFormatException,
    );
    final imported = importCardText(source, filename: 'different-file.json');
    expect(Sl1Profile.parse(exportSl1Card(imported)).json['name'], 'Synthetic');
  });
  test('geometry changes reject without losing canonical observations', () {
    final profile = fixture();
    profile.json['classic']['blocks'][1] = {
      'data': '${'AB' * 15}??',
      'status': 'read',
      'key': 'B',
      'errors': [
        {'key': 'A', 'status': 6, 'reason': 'Read failure'},
      ],
    };
    final card = sl1ToCard(profile);
    final before = card.sl1Profile!.export();
    card.tag = TagType.mifare1K;
    expect(() => reconcileSl1(card), throwsFormatException);
    expect(card.sl1Profile!.export(), before);
    card.tag = TagType.em410X;
    expect(() => reconcileSl1(card), throwsFormatException);
  });
  testWidgets(
    'approved identity/block-zero edit updates both stored representations',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      final partial = fixture();
      partial.json['classic']['blocks'][1] = {
        'data': '${'00' * 15}??',
        'status': 'read',
        'key': 'B',
        'errors': [
          {'key': 'A', 'status': 6, 'reason': 'Synthetic failure'},
        ],
      };
      partial.json['classic']['blocks'][3] = {
        'data': '${'??' * 6}FF078069${'??' * 6}',
        'status': 'read',
        'key': 'A',
        'errors': [
          {'key': 'B', 'status': 6, 'reason': 'Synthetic failure'},
        ],
      };
      final card = sl1ToCard(partial);
      preferences.setCards([card]);
      final app = ChameleonGUIState(preferences)
        ..log = Logger(level: Level.off);
      final key = GlobalKey<CardEditMenuState>();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => CardEditMenu(key: key, tagSave: card),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      key.currentState!.uidController.text = '11 22 33 44';
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      final saved = preferences.getCards().single;
      expect(saved.data[0].sublist(0, 4), [0x11, 0x22, 0x33, 0x44]);
      final exported = Sl1Profile.parse(exportSl1Card(saved));
      expect(
        exported.json['classic']['blocks'][0]['data'],
        Sl1Profile.encodeBytes(saved.data[0]),
      );
      expect(
        exported.json['classic']['blocks'][1],
        partial.json['classic']['blocks'][1],
      );
      expect(
        exported.json['classic']['blocks'][3],
        partial.json['classic']['blocks'][3],
      );
      expect(exported.json['classic']['provenance'], 'legacy-unverified');
      expect(exported.json['cardAuth']['enabled'], isFalse);
      expect(exported.json['cardAuth']['verification'], {
        'status': 'provided',
        'evidence': null,
      });
      expect(() => exported.image(), throwsFormatException);
    },
  );
}
