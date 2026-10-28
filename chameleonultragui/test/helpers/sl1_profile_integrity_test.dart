import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/sl1_profile_status.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'sl1_profile_test.dart' show fixture;
import 'sl1_card_workflows_test.dart'
    show appFor, host, MetadataDevice, SlotRouteProbe, SlotRouteProbeState;
import 'sl1_routes_test.dart' show acquisition, ProfileRouteDevice;
import 'sl1_staged_save_test.dart' show StagedProfileDevice;

class DelayedNicknameDevice extends MetadataDevice {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    if (cmd == ChameleonCommand.saveSlotNicks) {
      entered.complete();
      await release.future;
    }
    return super.sendCmd(
      cmd,
      data: data,
      timeout: timeout,
      skipReceive: skipReceive,
      firstRun: firstRun,
    );
  }
}

class FailingSaveStateDevice extends StagedProfileDevice {
  bool saved = false;
  bool statusUnavailable = false;
  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    final response = await super.sendCmd(
      cmd,
      data: data,
      timeout: timeout,
      skipReceive: skipReceive,
      firstRun: firstRun,
    );
    if (cmd == ChameleonCommand.sl1Save) {
      saved = true;
      extraFlags |= 0x40;
      response!.status = 0x66;
    }
    if (cmd == ChameleonCommand.sl1Status && saved && statusUnavailable) {
      response!.status = 0x67;
    }
    return response;
  }
}

class NonReadableBDevice extends ProfileRouteDevice {
  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    final response = await super.sendCmd(
      cmd,
      data: data,
      timeout: timeout,
      skipReceive: skipReceive,
      firstRun: firstRun,
    );
    if (cmd == ChameleonCommand.mf1ReadBlock &&
        data![1] % 4 == 3 &&
        response!.status == 0) {
      response.data = Sl1Profile.bytes('0000000000007F078869FFFFFFFFFFFF');
    }
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failure in [false, true]) {
    testWidgets(
      'disposed slot upload finishes persistence without UI update failure=$failure',
      (tester) async {
        final card = sl1ToCard(fixture());
        final app = await appFor(card);
        final device = DelayedNicknameDevice()..failNickname = failure;
        app.communicator = device;
        final key = GlobalKey<SlotRouteProbeState>();
        await tester.pumpWidget(host(app, SlotRouteProbe(key: key)));
        final pending = key.currentState!.onTap(
          card,
          (_, _) {},
          await AppLocalizations.delegate.load(const Locale('en')),
        );
        await device.entered.future;
        await tester.pumpWidget(const SizedBox());
        device.release.complete();
        await expectLater(pending, completes);
        expect(device.calls.where((c) => c == 4048), hasLength(1));
        expect(
          device.calls.where((c) => c == ChameleonCommand.saveSlotNicks.value),
          hasLength(1),
        );
      },
    );
  }
  for (final unavailable in [false, true]) {
    testWidgets(
      'failed SAVE refreshes durable state and retains error unknown=$unavailable',
      (tester) async {
        final device = FailingSaveStateDevice()
          ..statusUnavailable = unavailable;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Sl1SlotDialog(slot: 3, uploader: device.sl1Uploader),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save staged profile'));
        await tester.pumpAndSettle();
        expect(find.textContaining('status 102'), findsOneWidget);
        for (final label in ['Enable', 'Disable', 'Clear CardAuth']) {
          expect(
            tester
                .widget<TextButton>(find.widgetWithText(TextButton, label))
                .onPressed,
            isNull,
          );
        }
        expect(device.calls.where((c) => c == 4048), hasLength(1));
        expect(
          device.calls.where((c) => c == 4045).length,
          greaterThanOrEqualTo(3),
        );
        if (!unavailable) {
          expect(
            find.textContaining('An incomplete profile save is pending'),
            findsOneWidget,
          );
        }
      },
    );
  }
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'uid': (p) => p['uid'] = 'DEADBEEF',
    'type': (p) => p['tag'] = 1003,
    'ATQA': (p) => p['atqa'] = [0x12, 0x34],
    'SAK': (p) => p['sak'] = 9,
    'ATS': (p) => p['ats'] = [3, 0x75, 0x80],
    'memory': (p) => p['data'][0][0] = 1,
    'composite': (p) =>
        p['data'] = List.generate(72, (_) => List.filled(16, 0)),
  };
  for (final entry in mutations.entries) {
    test('native deserialization rejects conflicting ${entry.key}', () {
      final native =
          jsonDecode(sl1ToCard(fixture()).toJson()) as Map<String, dynamic>;
      entry.value(native);
      expect(
        () => CardSave.fromJson(jsonEncode(native)),
        throwsFormatException,
      );
    });
  }
  test('bound readable trailer B replaces stale provided key without guessed bytes', () async {
    final device = ProfileRouteDevice();
    final (r, card) = await acquisition(device);
    r.setKeyAsFound(0, 1, Uint8List(6));
    await r.dumpData();
    card.data = r.cardData;
    final profile = r.profileFor(card);
    expect(profile.json['classic']['keys'][0]['b']['value'], 'FFFFFFFFFFFF');
    expect(() => profile.image(), returnsNormally);
    expect(
      profile.json['classic']['keys'][0]['b']['evidence'],
      contains('bytes read'),
    );
    expect(r.cardData[3].sublist(10), everyElement(255));
  });
  test('partial projections and explicit trailer-key fills are the only valid native substitutions', () {
    final profile = fixture();
    profile.json['classic']['blocks'][3]['data'] =
        '${'??' * 6}FF078069${'??' * 6}';
    final card = sl1ToCard(profile);
    expect(() => CardSave.fromJson(card.toJson()), returnsNormally);
    card.data[3] = Sl1Profile.bytes('FFFFFFFFFFFFFF078069FFFFFFFFFFFF');
    expect(() => CardSave.fromJson(card.toJson()), returnsNormally);
    card.sl1Profile!.json['classic']['keys'][0]['b'] = {
      'value': null,
      'status': 'unknown',
      'evidence': null,
    };
    expect(() => CardSave.fromJson(card.toJson()), throwsFormatException);
    card.data[3] = Uint8List(0);
    expect(() => CardSave.fromJson(card.toJson()), returnsNormally);
    card.sl1Profile!.json['classic']['blocks'][0]['data'] = '${'00' * 15}??';
    card.data[0] = Uint8List(16);
    expect(() => CardSave.fromJson(card.toJson()), throwsFormatException);
    card.data[0] = Uint8List(0);
    expect(() => CardSave.fromJson(card.toJson()), returnsNormally);
  });
  test('folder native records reject embedded mismatches without dropping profile fields', () {
    final card = sl1ToCard(fixture());
    final source = CardFolderBundle(
      rootFolderId: 'synthetic',
      folders: [CardFolder(id: 'synthetic', name: 'Synthetic')],
      cards: [card],
    ).toJson();
    final json = jsonDecode(source);
    json['cards'][0]['uid'] = 'DEADBEEF';
    expect(
      () => CardFolderBundle.fromJson(jsonEncode(json)),
      throwsFormatException,
    );
  });
  testWidgets(
    'mutated in-memory native card is rejected before profile upload or export',
    (tester) async {
      final card = sl1ToCard(fixture());
      final app = await appFor(card);
      final device = MetadataDevice();
      app.communicator = device;
      card.uid = 'DEADBEEF';
      expect(() => exportSl1Card(card), throwsFormatException);
      expect(() => classicExportBytesForCard(card), throwsFormatException);
      final key = GlobalKey<SlotRouteProbeState>();
      await tester.pumpWidget(host(app, SlotRouteProbe(key: key)));
      final pending = key.currentState!.onTap(
        card,
        (_, _) {},
        await AppLocalizations.delegate.load(const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Profile upload stopped'), findsOneWidget);
      expect(find.textContaining('UID'), findsOneWidget);
      expect(device.calls, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await pending;
    },
  );
  test(
    'non-readable B remains provided and never becomes an observed key',
    () async {
      final device = NonReadableBDevice();
      final (r, card) = await acquisition(device);
      r.setKeyAsFound(0, 1, Uint8List(6));
      await r.dumpData();
      card.data = r.cardData;
      final p = r.profileFor(card);
      expect(p.json['classic']['keys'][0]['b']['value'], '000000000000');
      expect(p.json['classic']['keys'][0]['b']['status'], 'provided');
      expect(p.json['classic']['keys'][0]['b']['evidence'], isNull);
      expect(
        (p.json['classic']['blocks'][3]['data'] as String).substring(20),
        '??' * 6,
      );
    },
  );

  for (final escaped in [false, true]) {
    for (final folder in [false, true]) {
      test(
        'raw container rejects embedded duplicate AES key folder=$folder escaped=$escaped',
        () {
          final card = sl1ToCard(fixture());
          final bundle = CardFolderBundle(
            rootFolderId: 'synthetic',
            folders: [CardFolder(id: 'synthetic', name: 'Synthetic')],
            cards: [card],
          );
          final duplicate = escaped ? r'"k\u0065y"' : '"key"';
          final source = folder ? bundle.toJson() : card.toJson();
          final altered = source.replaceFirst(
            '"key":"00112233445566778899AABBCCDDEEFF"',
            '"key":"00112233445566778899AABBCCDDEEFF",$duplicate:"FFEEDDCCBBAA99887766554433221100"',
          );
          expect(altered, isNot(source));
          if (folder) {
            expect(
              () => CardFolderBundle.fromJson(altered),
              throwsFormatException,
            );
          } else {
            expect(() => CardSave.fromJson(altered), throwsFormatException);
          }
        },
      );
    }
  }
}
