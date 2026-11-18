import 'package:chameleonultragui/gui/component/mifare/classic.dart';
import 'package:chameleonultragui/helpers/card_save_converters.dart';

import 'dart:convert';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/view.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';

import 'sl1_routes_test.dart' show ProfileRouteDevice, acquisition;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/pages/dump_editor.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/helpers/card_file_import.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'sl1_profile_test.dart' show fixture;

Future<ChameleonGUIState> appFor(CardSave card) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = SharedPreferencesProvider();
  await prefs.load();
  prefs.setCards([card]);
  return ChameleonGUIState(prefs)..log = Logger(level: Level.off);
}

Widget host(ChameleonGUIState app, Widget child) =>
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

class Ev1SaveProbe extends MifareClassicHelper {
  const Ev1SaveProbe({
    super.key,
    required super.hfInfo,
    required super.mfcInfo,
  });
  @override
  Ev1SaveProbeState createState() => Ev1SaveProbeState();
}

class Ev1SaveProbeState extends CardReaderState {
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class CapturedCardExport extends FilePickerPlatform {
  Uint8List? bytes;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.bytes = Uint8List.fromList(bytes);
    return Uri.parse('file:///synthetic-export');
  }
}

class SlotRouteProbe extends SlotManagerPage {
  const SlotRouteProbe({super.key});
  @override
  SlotRouteProbeState createState() => SlotRouteProbeState();
}

class SlotRouteProbeState extends SlotManagerPageState {
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class ReadRouteProbe extends ReadCardPage {
  const ReadRouteProbe({super.key});
  @override
  ReadRouteProbeState createState() => ReadRouteProbeState();
}

class ReadRouteProbeState extends ReadCardPageState {
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class DelayedOverrideDevice extends ProfileRouteDevice {
  final gate = Completer<void>();
  @override
  Future<CardData?> scan14443aTag() async {
    await gate.future;
    return identity;
  }
}

class MetadataDevice extends ProfileRouteDevice {
  bool failNickname = false;
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
    if (failNickname && cmd == ChameleonCommand.saveSlotNicks) {
      response!.status = 0x66;
    }
    return response;
  }
}

void main() {
  test(
    'native embedded profiles and incidental marker names import normally',
    () {
      final card = sl1ToCard(fixture());
      expect(
        importCardText(card.toJson(), filename: 'native.json').sl1Profile!.json,
        card.sl1Profile!.json,
      );
      card.sl1Profile = null;
      card.name = 'chameleon-sl1-profile documentation';
      expect(
        importCardText(card.toJson(), filename: 'native.json').uid,
        card.uid,
      );
    },
  );
  test('EV1 composite is rejected by common v1 projection', () {
    final card = CardSave(
      uid: '01020304',
      name: 'Synthetic EV1',
      tag: TagType.mifare1K,
      sak: 8,
      atqa: Uint8List.fromList([0, 4]),
      data: List.generate(72, (_) => Uint8List(16)),
    );
    expect(() => legacySl1(card), throwsFormatException);
  });
  test('no-op editor reconciliation preserves binding and provenance', () {
    final card = sl1ToCard(fixture());
    card.sl1Profile!.json['cardAuth']['verification'] = {
      'status': 'verified',
      'evidence': 'Synthetic',
    };
    final original = card.sl1Profile!.export();
    reconcileSl1(card, memoryChanged: true);
    expect(card.sl1Profile!.export(), original);
  });
  testWidgets(
    'partial editor keeps absolute block placeholders and saves unrelated changes',
    (tester) async {
      final p = fixture();
      p.json['classic']['blocks'][1]['data'] = '${'00' * 15}??';
      final card = sl1ToCard(p);
      final app = await appFor(card);
      final key = GlobalKey<DumpEditorState>();
      List<Uint8List>? saved;
      await tester.pumpWidget(
        host(
          app,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DumpEditor(
                    key: key,
                    cardSave: card,
                    onSave: (data) {
                      saved = data;
                    },
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(key.currentState!.controllers[0].text.split('\n'), hasLength(4));
      final lines = key.currentState!.controllers[0].text.split('\n');
      lines[0] = '11 ${List.filled(15, '00').join(' ')}';
      key.currentState!.controllers[0].text = lines.join('\n');
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved![1], isEmpty);
      expect(saved![2], card.data[2]);
    },
  );
  testWidgets('invalid ATS edit displays an error and preserves saved card', (
    tester,
  ) async {
    final card = sl1ToCard(fixture());
    final app = await appFor(card);
    final original = card.toJson();
    final key = GlobalKey<CardEditMenuState>();
    await tester.pumpWidget(
      host(
        app,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CardEditMenu(key: key, tagSave: card),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    key.currentState!.atsController.text = '01 75';
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Card edit failed'), findsOneWidget);
    expect(app.sharedPreferencesProvider.getCards().single.toJson(), original);
    expect(key.currentState, isNotNull);
  });
  testWidgets('partial saved binary export shows an actionable error', (
    tester,
  ) async {
    final card = sl1ToCard(fixture());
    card.sl1Profile!.json['classic']['blocks'][0]['data'] = '??' * 16;
    card.data[0] = Uint8List(0);
    final app = await appFor(card);
    await tester.pumpWidget(
      host(
        app,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => saveTag(card, context, true),
            child: const Text('Export'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Card export failed'), findsOneWidget);
    expect(find.textContaining('JSON'), findsWidgets);
  });
  testWidgets(
    'EV1 exports retain all72 native blocks and reject incomplete binary',
    (tester) async {
      final picker = CapturedCardExport();
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      final card = CardSave(
        uid: '01020304',
        name: 'Synthetic EV1',
        tag: TagType.mifare1K,
        sak: 8,
        atqa: Uint8List.fromList([0, 4]),
        data: List.generate(72, (i) => Uint8List.fromList(List.filled(16, i))),
      );
      final app = await appFor(card);
      await tester.pumpWidget(
        host(
          app,
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => saveTag(card, context, true),
                  child: const Text('Binary'),
                ),
                TextButton(
                  onPressed: () => saveTag(card, context, false),
                  child: const Text('JSON'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Binary'));
      await tester.pumpAndSettle();
      expect(picker.bytes, hasLength(1152));
      expect(picker.bytes!.sublist(1136), everyElement(71));
      card.data[65] = Uint8List(0);
      picker.bytes = null;
      await tester.tap(find.text('Binary'));
      await tester.pumpAndSettle();
      expect(find.text('Card export failed'), findsOneWidget);
      expect(picker.bytes, isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      final native = CardSave.fromJson(utf8.decode(picker.bytes!));
      expect(native.data, hasLength(72));
      expect(native.data[65], isEmpty);
      expect(native.data[66], everyElement(66));
    },
  );
  testWidgets('unchanged actual library dump Save preserves profile binding', (
    tester,
  ) async {
    final card = sl1ToCard(fixture());
    card.sl1Profile!.json['cardAuth']['verification'] = {
      'status': 'verified',
      'evidence': 'Synthetic',
    };
    final original = card.sl1Profile!.export();
    final app = await appFor(card);
    await tester.pumpWidget(
      host(
        app,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CardViewMenu(tagSave: card, onMove: (_) async {}),
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
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    expect(
      app.sharedPreferencesProvider.getCards().single.sl1Profile!.export(),
      original,
    );
  });
  for (final failure in [false, true]) {
    testWidgets(
      'profile commit nickname persistence failure=$failure is distinct',
      (tester) async {
        final card = sl1ToCard(fixture());
        final app = await appFor(card);
        final device = MetadataDevice()..failNickname = failure;
        app.communicator = device;
        final key = GlobalKey<SlotRouteProbeState>();
        await tester.pumpWidget(host(app, SlotRouteProbe(key: key)));
        key.currentState!.gridPosition = 3;
        final pending = key.currentState!.onTap(
          card,
          (_, _) {},
          await AppLocalizations.delegate.load(const Locale('en')),
        );
        await tester.pumpAndSettle();
        if (failure) {
          expect(find.text('Profile saved; slot name failed'), findsOneWidget);
          expect(find.textContaining('status 102'), findsOneWidget);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        }
        await pending;
        expect(device.calls.where((c) => c == 4048), hasLength(1));
        final nickname = device.calls.indexOf(
          ChameleonCommand.setSlotTagNick.value,
        );
        expect(nickname, greaterThan(device.calls.indexOf(4048)));
        expect(device.payloads[nickname].first, 3);
        expect(utf8.decode(device.payloads[nickname].sublist(2)), card.name);
        expect(device.calls.last, ChameleonCommand.saveSlotNicks.value);
      },
    );
  }
  test('malformed non-json member escape is classified without throwing', () {
    final bytes = Uint8List.fromList(utf8.encode(r'{"bad\q":1}'));
    expect(isStructuredCardFile(bytes, filename: 'bad.bin'), isTrue);
    expect(
      () => importCardText(utf8.decode(bytes), filename: 'bad.bin'),
      throwsFormatException,
    );
  });
  test('masked unsupported text geometry is rejected losslessly', () {
    final flipper =
        'Filetype: Flipper NFC device\nUID: 01020304\nSAK: 09\nATQA: 0004\nBlock 0: ${'AB' * 16}??\nBlock 1: ${'CD' * 17}';
    expect(
      () => importCardText(flipper, filename: 'masked.nfc'),
      throwsFormatException,
    );
    final mct = '+Sector: 0\n0102030400090400${'AB' * 8}??\n${'CD' * 17}';
    expect(
      () => importCardText(mct, filename: 'masked.mct'),
      throwsFormatException,
    );
  });
  testWidgets(
    'pending override rejects overlap and cancellation prevents late commit',
    (tester) async {
      final app = await appFor(sl1ToCard(fixture()));
      final device = DelayedOverrideDevice();
      app.communicator = device;
      final key = GlobalKey<ReadRouteProbeState>();
      await tester.pumpWidget(host(app, ReadRouteProbe(key: key)));
      final state = key.currentState!;
      state.hfInfo = HFCardInfo(
        uid: '01020304',
        sak: '09',
        atqa: '12 34',
        ats: '02 75',
        type: TagType.mifareMini,
      );
      final previous = state.mfcInfo;
      final first = state.applyTypeOverride(TagType.unknown);
      final second = state.applyTypeOverride(TagType.unknown);
      state.cancelTypeOverride();
      device.gate.complete();
      expect(await second, isFalse);
      expect(await first, isFalse);
      expect(state.hfInfo.type, TagType.mifareMini);
      expect(state.mfcInfo, same(previous));
    },
  );
  testWidgets(
    'failed bound type override leaves displayed type and session unchanged',
    (tester) async {
      final card = sl1ToCard(fixture());
      final app = await appFor(card);
      final device = ProfileRouteDevice()..changeAtScan = 1;
      app.communicator = device;
      final key = GlobalKey<ReadRouteProbeState>();
      await tester.pumpWidget(host(app, ReadRouteProbe(key: key)));
      final state = key.currentState!;
      state.hfInfo = HFCardInfo(
        uid: '01020304',
        sak: '09',
        atqa: '12 34',
        ats: '02 75',
        type: TagType.mifareMini,
        tech: 'Original Mini',
      );
      final previous = state.mfcInfo;
      final pending = state.applyTypeOverride(TagType.mifare1K);
      await tester.pumpAndSettle();
      expect(find.text('Card type change failed'), findsOneWidget);
      expect(state.hfInfo.type, TagType.mifareMini);
      expect(state.hfInfo.tech, 'Original Mini');
      expect(state.mfcInfo, same(previous));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(await pending, isFalse);
      device.changeAtScan = null;
      expect(await state.applyTypeOverride(TagType.mifare1K), isTrue);
      await tester.pumpAndSettle();
      expect(state.hfInfo.type, TagType.mifare1K);
      expect(state.mfcInfo.type, MifareClassicType.m1k);
      expect(state.mfcInfo.state, MifareClassicState.checkKeys);
      expect(state.mfcInfo, isNot(same(previous)));
    },
  );
  testWidgets(
    'live EV1 library save retains72 blocks and complete binary export',
    (tester) async {
      final device = ProfileRouteDevice();
      final (recovery, card) = await acquisition(device);
      recovery.isMifareClassicEV1 = true;
      recovery.mifareClassicType = MifareClassicType.m1k;
      for (var sector = 0; sector < 18; sector++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          recovery.setKeyAsFound(
            sector,
            keyType,
            Uint8List.fromList(List.filled(6, 255)),
          );
        }
      }
      await recovery.dumpData();
      final app = await appFor(card);
      app.sharedPreferencesProvider.setCards([]);
      final key = GlobalKey<Ev1SaveProbeState>();
      final picker = CapturedCardExport();
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      await tester.pumpWidget(
        host(
          app,
          Ev1SaveProbe(
            key: key,
            hfInfo: HFCardInfo(
              uid: card.uid,
              atqa: bytesToHexSpace(card.atqa),
              sak: '09',
              ats: '02 75',
              type: TagType.mifare1K,
            ),
            mfcInfo: MifareClassicInfo(
              type: MifareClassicType.m1k,
              isEV1: true,
              state: MifareClassicState.save,
            )..recovery = recovery,
          ),
        ),
      );
      await key.currentState!.saveCard();
      final saved = app.sharedPreferencesProvider.getCards().single;
      expect(saved.sl1Profile, isNull);
      expect(saved.data, hasLength(72));
      expect(saved.data[71], recovery.cardData[71]);
      expect(() => recovery.profileFor(saved), throwsFormatException);
      await key.currentState!.saveCard(bin: true);
      expect(picker.bytes, hasLength(1152));
      recovery.cardData[65] = Uint8List(0);
      picker.bytes = null;
      final pending = key.currentState!.saveCard(bin: true);
      await tester.pumpAndSettle();
      expect(find.text('Incomplete Classic image'), findsOneWidget);
      expect(picker.bytes, isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await pending;
    },
  );
  test('complete EV1 Flipper import remains native and partial composite rejects explicitly', () {
    final source = [
      'Filetype: Flipper NFC device',
      'UID: 01 02 03 04',
      'SAK: 08',
      'ATQA: 04 00',
      for (var i = 0; i < 72; i++) 'Block $i: ${'00' * 16}',
    ].join('\n');
    final card = flipperNfcToCardSave(source);
    expect(card.sl1Profile, isNull);
    expect(card.data, hasLength(72));
    expect(classicExportBytesForCard(card), hasLength(1152));
    expect(
      () => flipperNfcToCardSave(
        source.replaceFirst(
          'Block 65: ${'00' * 16}',
          'Block 65: ${'00' * 15}??',
        ),
      ),
      throwsFormatException,
    );
  });
  testWidgets(
    'historical composite profile cannot silently upload its64-block projection',
    (tester) async {
      final card = sl1ToCard(fixture(type: '1k'));
      card.data = List.generate(72, (_) => Uint8List(16));
      final app = await appFor(card);
      final device = MetadataDevice();
      app.communicator = device;
      final key = GlobalKey<SlotRouteProbeState>();
      await tester.pumpWidget(host(app, SlotRouteProbe(key: key)));
      final pending = key.currentState!.onTap(
        card,
        (_, _) {},
        await AppLocalizations.delegate.load(const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Profile upload stopped'), findsOneWidget);
      expect(find.textContaining('composite'), findsOneWidget);
      expect(device.calls, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await pending;
    },
  );
  testWidgets('failed CardView export keeps format and card dialogs open', (
    tester,
  ) async {
    final card = sl1ToCard(fixture());
    card.sl1Profile!.json['classic']['blocks'][0]['data'] = '??' * 16;
    card.data[0] = Uint8List(0);
    final app = await appFor(card);
    final original = card.toJson();
    await tester.pumpWidget(
      host(
        app,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CardViewMenu(tagSave: card, onMove: (_) async {}),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.download_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('.bin'));
    await tester.pumpAndSettle();
    expect(find.text('Card export failed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNWidgets(2));
    expect(find.textContaining('.bin'), findsOneWidget);
    expect(app.sharedPreferencesProvider.getCards().single.toJson(), original);
  });
}
