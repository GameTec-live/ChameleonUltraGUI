import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/mifare_value_blocks.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/dump_analyzer.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/value_blocks.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestSerial extends Fake implements AbstractSerial {
  @override
  ConnectionType get connectionType => ConnectionType.usb;
  @override
  bool get connected => true;
}

class ValueBlockCommunicator extends ChameleonCommunicator {
  ValueBlockCommunicator() : super(Logger(level: Level.off));
  final calls = <(ChameleonCommand, Uint8List?)>[];
  final memory = <int, Uint8List>{
    4: hexToBytes(MifareClassicDumpAnalyzer.intToValueBlock(-42, 4)),
    8: hexToBytes(MifareClassicDumpAnalyzer.intToValueBlock(100, 8)),
  };
  Uint8List currentUid = hexToBytes('11223344');
  int status = 0;
  Completer<void>? modeGate;
  bool rejectReadback = false;
  bool dictionaryFindsKeys = true;

  @override
  Future<bool> isReaderDeviceMode() async => true;
  @override
  Future<CardData?> scan14443aTag() async => CardData(
    uid: currentUid,
    sak: 8,
    atqa: hexToBytes('0400'),
    ats: Uint8List(0),
  );
  @override
  Future<bool> detectMf1Support() async => true;
  @override
  Future<NTLevel> getMf1NTLevel() async => NTLevel.weak;
  @override
  Future<bool> mf1Auth(int block, int type, Uint8List key,
          {bool strict = false}) async =>
      dictionaryFindsKeys && block != 0x45;
  @override
  Future<Uint8List?> mf1AuthMultipleKeys(
    int block,
    int type,
    List<Uint8List> keys,
  ) async => keys.isEmpty || !dictionaryFindsKeys ? null : keys.first;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) async {
    calls.add((cmd, data));
    var payload = Uint8List(0);
    if (cmd == ChameleonCommand.getDeviceCapabilities) {
      payload = Uint8List.fromList([0x07, 0xD8, 0x07, 0xD9, 0x07, 0xDB]);
    } else if (cmd == ChameleonCommand.changeDeviceMode) {
      await modeGate?.future;
    } else if (cmd == ChameleonCommand.mf1ReadBlock && !rejectReadback) {
      final block = data![1];
      payload =
          memory[block] ??
          (block % 4 == 3
              ? hexToBytes('FFFFFFFFFFFFFF078069FFFFFFFFFFFF')
              : Uint8List(16));
    } else if (cmd == ChameleonCommand.mf1WriteBlock && status == 0) {
      memory[data![1]] = Uint8List.fromList(data.sublist(8));
    } else if (cmd == ChameleonCommand.mf1ManipulateValueBlock && status == 0) {
      final source = data![1], destination = data[14];
      final value = MifareClassicDumpAnalyzer.valueBlockToInt(
        bytesToHex(memory[source]!),
      )!;
      final amount = ByteData.sublistView(data, 9, 13).getInt32(0, Endian.big);
      final result = data[8] == 0xC1
          ? value + amount
          : data[8] == 0xC0
          ? value - amount
          : value;
      memory[destination] = hexToBytes(
        MifareClassicDumpAnalyzer.intToValueBlock(result, source),
      );
    }
    return ChameleonMessage(command: cmd.value, status: status, data: payload);
  }
}

Future<ChameleonGUIState> appState(ValueBlockCommunicator c) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = SharedPreferencesProvider();
  await preferences.load();
  return ChameleonGUIState(preferences)
    ..communicator = c
    ..connector = TestSerial()
    ..log = Logger(level: Level.off);
}

Future<MifareValueBlocks> session(
  ValueBlockCommunicator c, {
  MifareClassicType type = MifareClassicType.mini,
  bool isEV1 = false,
}) async {
  final app = await appState(c);
  final recovery = MifareClassicRecovery(
    appState: app,
    update: () {},
    localizations: await AppLocalizations.delegate.load(const Locale('en')),
    mifareClassicType: type,
    isMifareClassicEV1: isEV1,
  );
  for (
    var sector = 0;
    sector < mfClassicGetSectorCount(type, isEV1: isEV1);
    sector++
  ) {
    recovery.setKeyAsFound(sector, 0, hexToBytes('FFFFFFFFFFFF'));
    recovery.setKeyAsFound(sector, 1, hexToBytes('A0A1A2A3A4A5'));
  }
  return MifareValueBlocks(
    communicator: c,
    recovery: recovery,
    uid: '11 22 33 44',
    capabilities: {2008, 2009, 2011},
  );
}

Future<ChameleonGUIState> pumpTool(
  WidgetTester tester,
  ValueBlockCommunicator c, {
  bool toolsPage = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final app = await appState(c);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: toolsPage ? const ToolsPage() : const MifareValueBlocksTool(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

Future<void> discover(WidgetTester tester) async {
  await tester.tap(find.text('Scan card'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Check keys from dictionary'));
  await tester.pumpAndSettle();
}

void main() {
  test('firmware command preserves independent keys, signed byte order, and failures', () async {
    final c = ValueBlockCommunicator();
    c.status = 6;
    await expectLater(
      c.manipulateValueBlock(
        4,
        0x60,
        hexToBytes('010203040506'),
        MifareClassicValueBlockOperator.decrement,
        -2,
        128,
        0x61,
        hexToBytes('060504030201'),
      ),
      throwsStateError,
    );
    expect(c.calls.single.$2, [
      0x60,
      4,
      1,
      2,
      3,
      4,
      5,
      6,
      0xC0,
      0xFF,
      0xFF,
      0xFF,
      0xFE,
      0x61,
      128,
      6,
      5,
      4,
      3,
      2,
      1,
    ]);
  });

  test(
    'layout includes EV1 and 4K geometry while protecting reserved blocks',
    () async {
      final ev1 = await session(
        ValueBlockCommunicator(),
        type: MifareClassicType.m1k,
        isEV1: true,
      );
      expect(ev1.blockCount, 72);
      expect(ev1.isDataBlock(64), isTrue);
      expect(ev1.isDataBlock(69), isTrue);
      expect(ev1.isDataBlock(71), isFalse);
      expect(ev1.isDataBlock(72), isFalse);
      final large = await session(
        ValueBlockCommunicator(),
        type: MifareClassicType.m4k,
      );
      expect(large.sectorCount, 40);
      for (final block in [0, 3, 127, 143, 255, 256]) {
        expect(large.isDataBlock(block), isFalse);
      }
      expect(large.isDataBlock(142), isTrue);
    },
  );

  test('automatic authentication respects source and destination access conditions', () async {
    final c = ValueBlockCommunicator();
    final card = await session(c);
    await card.refresh();
    // Source increment requires B; destination allows decrement/transfer with A or B.
    card.blocks[7] = hexToBytes(
      'FFFFFFFFFFFF${MifareClassicDumpAnalyzer.encodeAccessConditions([3, 0, 0, 1])}69FFFFFFFFFFFF',
    );
    card.blocks[11] = hexToBytes(
      'FFFFFFFFFFFF${MifareClassicDumpAnalyzer.encodeAccessConditions([4, 0, 0, 1])}69FFFFFFFFFFFF',
    );
    await card.apply(ValueBlockOperation.increment, 4, 8, 2);
    final call = c.calls.last;
    expect(call.$1, ChameleonCommand.mf1ManipulateValueBlock);
    expect(call.$2!.sublist(0, 8), [
      0x61,
      4,
      0xA0,
      0xA1,
      0xA2,
      0xA3,
      0xA4,
      0xA5,
    ]);
    expect(call.$2!.sublist(13), [0x60, 8, 255, 255, 255, 255, 255, 255]);
    expect(card.blocks[8], isNull);
    await card.readBlock(8);
    expect(card.value(8), -40);
  });

  test('write initializes selected block; transfer preserves source value and address', () async {
    final c = ValueBlockCommunicator();
    final card = await session(c);
    await card.refresh();
    await card.apply(ValueBlockOperation.write, 5, 5, -2147483648);
    await card.readBlock(5);
    expect(card.value(5), -2147483648);
    expect(card.address(5), 5);
    await card.apply(ValueBlockOperation.transfer, 5, 8, 0);
    await card.readBlock(8);
    expect(card.value(8), -2147483648);
    expect(card.address(8), 5);
  });

  test(
    'mutations snapshot keys and refuse a different physical card',
    () async {
      final c = ValueBlockCommunicator();
      final card = await session(c);
      await card.refresh();
      c.modeGate = Completer<void>();
      final operation = card.apply(ValueBlockOperation.increment, 4, 8, 7);
      card.recovery.getSectorKey(1, 0).fillRange(0, 6, 0);
      c.modeGate!.complete();
      await operation;
      expect(c.calls.last.$2!.sublist(2, 8), [255, 255, 255, 255, 255, 255]);
      await card.readBlock(4);
      c.currentUid = hexToBytes('55667788');
      c.calls.clear();
      await expectLater(
        card.apply(ValueBlockOperation.increment, 4, 8, 1),
        throwsStateError,
      );
      expect(
        c.calls.where(
          (call) => call.$1 == ChameleonCommand.mf1ManipulateValueBlock,
        ),
        isEmpty,
      );
    },
  );

  test(
    'failed mutations invalidate cached destination without retrying',
    () async {
      final c = ValueBlockCommunicator();
      final card = await session(c);
      await card.refresh();
      c.status = 6;
      c.calls.clear();
      await expectLater(
        card.apply(ValueBlockOperation.decrement, 4, 8, 1),
        throwsStateError,
      );
      expect(card.blocks[8], isNull);
      expect(
        c.calls.where(
          (call) => call.$1 == ChameleonCommand.mf1ManipulateValueBlock,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'saved dictionaries feed the existing recovery flow on narrow screens',
    (tester) async {
      final c = ValueBlockCommunicator();
      final app = await pumpTool(tester, c);
      app.sharedPreferencesProvider.setDictionaries([
        Dictionary(
          id: 'office',
          name: 'Office',
          keyLength: 12,
          keys: [hexToBytes('A0A1A2A3A4A5')],
        ),
      ]);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan card'));
      await tester.pumpAndSettle();
      final dropdown = find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<String>,
      );
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Office (1)').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.text('Check keys from dictionary'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check keys from dictionary'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Increment'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Increment'));
      await tester.pumpAndSettle();
      final payload = c.calls
          .lastWhere(
            (call) => call.$1 == ChameleonCommand.mf1ManipulateValueBlock,
          )
          .$2!;
      expect(payload.sublist(2, 8), [0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Tools opens a full page with dictionary recovery and visual operations',
    (tester) async {
      final c = ValueBlockCommunicator();
      await pumpTool(tester, c, toolsPage: true);
      await tester.tap(find.text('Live value blocks'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await discover(tester);
      expect(find.text('Recover keys'), findsNothing);
      expect(
        tester
            .widget<ExpansionTile>(find.byType(ExpansionTile))
            .controller!
            .isExpanded,
        isFalse,
      );
      expect(find.byType(Chip), findsNWidgets(2));
      expect(find.byType(KeyCheckMarks), findsNothing);
      final source = find.byKey(const ValueKey('value-block-4'));
      await tester.ensureVisible(source);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Increment'));
      await tester.pumpAndSettle();
      expect(
        MifareClassicDumpAnalyzer.valueBlockToInt(bytesToHex(c.memory[4]!)),
        -41,
      );
      expect(find.text('Card operation completed.'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      expect(find.byType(KeyCheckMarks), findsNothing);
    },
  );

  testWidgets('copy targeting never redirects in-place arithmetic or writing', (
    tester,
  ) async {
    final c = ValueBlockCommunicator();
    await pumpTool(tester, c);
    await discover(tester);
    await tester.tap(find.text('Copy between blocks'));
    await tester.pumpAndSettle();
    expect(find.text('Increment'), findsNothing);
    expect(find.text('Decrement'), findsNothing);
    expect(find.text('Write value'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget is FilledButton && widget.onPressed == null,
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    final target = find.byKey(const ValueKey('value-block-8'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy value'));
    await tester.pumpAndSettle();
    expect(
      MifareClassicDumpAnalyzer.valueBlockToInt(bytesToHex(c.memory[8]!)),
      -42,
    );
    final transfer = c.calls
        .lastWhere(
          (call) => call.$1 == ChameleonCommand.mf1ManipulateValueBlock,
        )
        .$2!;
    expect(transfer[1], 4);
    expect(transfer[14], 8);

    await tester.tap(find.text('Copy between blocks'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    for (final label in ['Increment', 'Decrement']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      final call = c.calls
          .lastWhere(
            (entry) => entry.$1 == ChameleonCommand.mf1ManipulateValueBlock,
          )
          .$2!;
      expect(call[1], 4);
      expect(call[14], 4);
      expect(
        MifareClassicDumpAnalyzer.valueBlockToInt(bytesToHex(c.memory[8]!)),
        -42,
      );
    }
    await tester.enterText(find.byType(TextField), '-7');
    await tester.tap(find.text('Write value'));
    await tester.pumpAndSettle();
    expect(
      MifareClassicDumpAnalyzer.valueBlockToInt(bytesToHex(c.memory[4]!)),
      -7,
    );
    expect(
      MifareClassicDumpAnalyzer.valueBlockToInt(bytesToHex(c.memory[8]!)),
      -42,
    );
    await tester.tap(find.text('Copy between blocks'));
    await tester.pumpAndSettle();
    expect(
      find.text('—'),
      findsOneWidget,
    ); // Each copy starts with no destination.
  });

  testWidgets(
    'dictionary check precedes recovery and progress clears the header buttons',
    (tester) async {
      final c = ValueBlockCommunicator()..dictionaryFindsKeys = false;
      await pumpTool(tester, c);
      await tester.tap(find.text('Scan card'));
      await tester.pumpAndSettle();
      expect(find.text('Recover keys'), findsNothing);
      await tester.tap(find.text('Check keys from dictionary'));
      await tester.pumpAndSettle();
      expect(find.text('Recover keys'), findsOneWidget);
      expect(find.text('Export found keys'), findsOneWidget);
      expect(find.text('Check keys from dictionary'), findsNothing);
      expect(
        tester
            .widget<ExpansionTile>(find.byType(ExpansionTile))
            .controller!
            .isExpanded,
        isTrue,
      );

      c.modeGate = Completer<void>();
      await tester.tap(find.text('Read blocks'));
      await tester.pump();
      final button = find
          .ancestor(
            of: find.text('Read blocks'),
            matching: find.byWidgetPredicate(
              (widget) => widget is OutlinedButton,
            ),
          )
          .first;
      final progress = tester.getRect(
        find.byKey(const ValueKey('value-progress')),
      );
      expect(
        progress.top,
        greaterThanOrEqualTo(tester.getRect(button).bottom + 12),
      );
      c.modeGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'resuming a skipped key restores recovery without resetting progress',
    (tester) async {
      final c = ValueBlockCommunicator()..dictionaryFindsKeys = false;
      await pumpTool(tester, c);
      await tester.tap(find.text('Scan card'));
      await tester.pumpAndSettle();
      for (var index = 0; index < 10; index++) {
        await tester.tap(find.byTooltip('Skip recovery').first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Check keys from dictionary'));
      await tester.pumpAndSettle();
      expect(find.byType(KeyCheckMarks), findsNothing);
      await tester.tap(find.text('Keys'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Resume recovery'), findsNWidgets(10));
      await tester.tap(find.byTooltip('Resume recovery').first);
      await tester.pumpAndSettle();
      expect(find.text('Recover keys'), findsOneWidget);
      expect(find.byTooltip('Resume recovery'), findsNWidgets(9));
      expect(find.byTooltip('Skip recovery'), findsOneWidget);
    },
  );
  testWidgets(
    'completed keys can be exported by reopening the collapsed panel',
    (tester) async {
      await pumpTool(tester, ValueBlockCommunicator());
      await discover(tester);
      expect(find.byType(KeyCheckMarks), findsNothing);
      await tester.tap(find.text('Keys'));
      await tester.pumpAndSettle();
      expect(find.text('Recover keys'), findsNothing);
      expect(find.text('Check keys from dictionary'), findsNothing);
      await tester.tap(find.text('Export found keys'));
      await tester.pumpAndSettle();
      expect(find.byType(DictionaryExportMenu), findsOneWidget);
      expect(
        tester
            .widget<DictionaryExportMenu>(find.byType(DictionaryExportMenu))
            .keys
            .where((key) => key.length == 6),
        hasLength(10),
      );
    },
  );
}
