import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/mifare/classic.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/view.dart';
import 'package:chameleonultragui/gui/menu/pages/dump_editor.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/card_file_import.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'sl1_profile_test.dart' show fixture;
import 'sl1_card_workflows_test.dart' show appFor, host, CapturedCardExport;
import 'sl1_routes_test.dart' show acquisition, ProfileRouteDevice;

Future<(MifareClassicRecovery, CardSave)> onlyBRead({bool ev1 = false}) async {
  final device = ProfileRouteDevice();
  final (r, card) = await acquisition(device);
  if (ev1) {
    r.mifareClassicType = MifareClassicType.m1k;
    r.isMifareClassicEV1 = true;
    card.tag = TagType.mifare1K;
  }
  for (var sector = 0; sector < (ev1 ? 18 : 5); sector++) {
    r.validKeys[sector] = Uint8List(0);
    r.checkMarks[sector] = ChameleonKeyCheckmark.none;
    r.setKeyAsFound(sector, 1, Uint8List.fromList(List.filled(6, 255)));
  }
  await r.dumpData();
  return (r, card);
}

MifareClassicHelper liveHelper(
  GlobalKey<CardReaderState> key,
  MifareClassicRecovery r,
  CardSave card,
) => MifareClassicHelper(
  key: key,
  hfInfo: HFCardInfo(
    uid: card.uid,
    sak: '09',
    atqa: '12 34',
    ats: '02 75',
    type: card.tag,
  ),
  mfcInfo: MifareClassicInfo(
    type: r.mifareClassicType,
    isEV1: r.isMifareClassicEV1,
    state: MifareClassicState.save,
  )..recovery = r,
);
void main() {
  for (final header in [
    '+Sector: 0\n',
    '{"id":"synthetic","uid":"01020304",',
    '{"Created":"proxmark3",',
    '{"format":"chameleon-ultra-gui-folder",',
  ]) {
    test('malformed UTF8 structured header stays structured: $header', () {
      final bytes = Uint8List(1024)..fillRange(0, 1024, 32);
      final prefix = utf8.encode(header);
      bytes.setRange(0, prefix.length, prefix);
      bytes[1023] = 255;
      expect(isStructuredCardFile(bytes, filename: 'synthetic.bin'), isTrue);
    });
  }
  testWidgets(
    'unrelated library edit preserves key-filled trailer observations and read evidence',
    (tester) async {
      final p = fixture();
      p.json['classic']['blocks'][3] = {
        'data': '${'??' * 6}FF078069${'??' * 6}',
        'status': 'read',
        'key': 'A',
        'errors': [
          {'key': 'B', 'status': 6, 'reason': 'Synthetic attempt'},
        ],
      };
      final card = sl1ToCard(p);
      card.data[3] = hexToBytes('FFFFFFFFFFFFFF078069FFFFFFFFFFFF');
      final original = jsonDecode(p.export())['classic']['blocks'][3];
      final app = await appFor(card);
      await tester.pumpWidget(
        host(
          app,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) =>
                    CardViewMenu(tagSave: card, onMove: (_) async {}),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_document));
      await tester.pumpAndSettle();
      final editor = tester.state<DumpEditorState>(find.byType(DumpEditor));
      final lines = editor.controllers[0].text.split('\n');
      lines[0] = '11 ${List.filled(15, '00').join(' ')}';
      editor.controllers[0].text = lines.join('\n');
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      final saved = app.sharedPreferencesProvider.getCards().single;
      expect(saved.sl1Profile!.json['classic']['blocks'][3], original);
      expect(
        saved.sl1Profile!.json['classic']['provenance'],
        'legacy-unverified',
      );
    },
  );
  testWidgets(
    'actual live edit and library save never promote masked KeyA zeros',
    (tester) async {
      final (r, card) = await onlyBRead();
      card.data = r.cardData;
      final original = r.profileFor(card).json['classic'];
      final app = await appFor(card);
      app.sharedPreferencesProvider.setCards([]);
      final key = GlobalKey<CardReaderState>();
      await tester.pumpWidget(
        host(app, Scaffold(body: liveHelper(key, r, card))),
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l.view_dump));
      await tester.pumpAndSettle();
      final editor = tester.state<DumpEditorState>(find.byType(DumpEditor));
      final lines = editor.controllers[0].text.split('\n');
      lines[0] = '11 ${List.filled(15, '00').join(' ')}';
      editor.controllers[0].text = lines.join('\n');
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      await key.currentState!.saveCard();
      final saved = app.sharedPreferencesProvider.getCards().single;
      final c = saved.sl1Profile!.json['classic'];
      expect(c['blocks'][3], original['blocks'][3]);
      expect(c['keys'][0]['b'], original['keys'][0]['b']);
      expect(c['keys'][0]['a']['status'], 'unknown');
      expect(() => classicExportBytesForCard(saved), throwsFormatException);
    },
  );
  testWidgets(
    'new live EV1 archive retains unknown key coverage and refuses binary',
    (tester) async {
      final (r, card) = await onlyBRead(ev1: true);
      final app = await appFor(card);
      app.sharedPreferencesProvider.setCards([]);
      final key = GlobalKey<CardReaderState>();
      final picker = CapturedCardExport();
      final old = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = old);
      await tester.pumpWidget(
        host(app, Scaffold(body: liveHelper(key, r, card))),
      );
      await key.currentState!.saveCard();
      final saved = app.sharedPreferencesProvider.getCards().single;
      expect(() => classicExportBytesForCard(saved), throwsFormatException);
      final json = jsonDecode(saved.toJson());
      expect(json['nativeClassicCoverage'], isNotNull);
      expect(json['nativeClassicCoverage']['version'], 1);
      expect(json['nativeClassicCoverage']['classic']['blocks'], hasLength(72));
      expect(json['nativeClassicCoverage']['classic']['keys'], hasLength(18));
      expect(
        json['nativeClassicCoverage']['classic']['keys'][0]['a']['status'],
        'unknown',
      );
      expect(
        json['nativeClassicCoverage']['classic']['keys'][0]['b']['status'],
        'verified',
      );
      expect(
        (json['nativeClassicCoverage']['classic']['blocks'][3]['data']
                as String)
            .substring(0, 12),
        '??' * 6,
      );
      final pending = key.currentState!.saveCard(bin: true);
      await tester.pumpAndSettle();
      expect(find.text('Incomplete Classic image'), findsOneWidget);
      expect(picker.bytes, isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await pending;
      expect(await saveTag(saved, key.currentState!.context, false), isTrue);
      final archived = CardSave.fromJson(utf8.decode(picker.bytes!));
      expect(
        archived.nativeClassicCoverage!.toNativeJson(),
        saved.nativeClassicCoverage!.toNativeJson(),
      );
      final corrupt = jsonDecode(utf8.decode(picker.bytes!));
      corrupt['nativeClassicCoverage']['version'] = 2;
      expect(
        () => CardSave.fromJson(jsonEncode(corrupt)),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'unchanged live editor save preserves read coverage and key evidence',
    (tester) async {
      final (r, card) = await onlyBRead();
      card.data = r.cardData;
      final original = r.profileFor(card).json['classic'];
      final app = await appFor(card);
      app.sharedPreferencesProvider.setCards([]);
      final key = GlobalKey<CardReaderState>();
      await tester.pumpWidget(
        host(app, Scaffold(body: liveHelper(key, r, card))),
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l.view_dump));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      await key.currentState!.saveCard();
      expect(
        app.sharedPreferencesProvider
            .getCards()
            .single
            .sl1Profile!
            .json['classic'],
        original,
      );
      expect(r.readCoverageEdited, isFalse);
    },
  );
  test(
    'legacy native EV1 archives remain raw and are not relabeled verified',
    () {
      final card = CardSave(
        uid: '01020304',
        name: 'Synthetic legacy',
        tag: TagType.mifare1K,
        sak: 8,
        atqa: Uint8List.fromList([0, 4]),
        data: List.generate(72, (_) => Uint8List(16)),
      );
      final restored = CardSave.fromJson(card.toJson());
      expect(restored.nativeClassicCoverage, isNull);
      expect(classicExportBytesForCard(restored), hasLength(1152));
      expect(
        jsonDecode(restored.toJson()).containsKey('nativeClassicCoverage'),
        isFalse,
      );
    },
  );
  testWidgets(
    'native EV1 library edit retains canonical unknowns and read key evidence',
    (tester) async {
      final (r, card) = await onlyBRead(ev1: true);
      final app = await appFor(card);
      app.sharedPreferencesProvider.setCards([]);
      final key = GlobalKey<CardReaderState>();
      await tester.pumpWidget(
        host(app, Scaffold(body: liveHelper(key, r, card))),
      );
      await key.currentState!.saveCard();
      final original = app.sharedPreferencesProvider.getCards().single;
      final coverage = original.nativeClassicCoverage!.copy();
      await tester.pumpWidget(
        host(
          app,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) =>
                    CardViewMenu(tagSave: original, onMove: (_) async {}),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_document));
      await tester.pumpAndSettle();
      final editor = tester.state<DumpEditorState>(find.byType(DumpEditor));
      final lines = editor.controllers[0].text.split('\n');
      lines[0] = '22 ${List.filled(15, '00').join(' ')}';
      editor.controllers[0].text = lines.join('\n');
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      final saved = app.sharedPreferencesProvider.getCards().single;
      final c = saved.nativeClassicCoverage!;
      expect(c.json['blocks'][3], coverage.json['blocks'][3]);
      expect(c.json['keys'][0], coverage.json['keys'][0]);
      expect(c.json['provenance'], 'legacy-unverified');
      expect(saved.data[3], isEmpty);
      expect(() => classicExportBytesForCard(saved), throwsFormatException);
    },
  );
}
