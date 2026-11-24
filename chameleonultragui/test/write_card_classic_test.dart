import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/gen2.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A card on the reader. [blocks] is 0 for a card that isn't MIFARE Classic.
class _Card {
  _Card({required this.uid, required this.blocks, this.gen1a = true});

  final List<int> uid;
  final int blocks;
  final bool gen1a;
}

/// A Chameleon in reader mode with [card] on it (or none), answering the raw
/// 14A commands the Gen1 writer sends.
class _Reader extends ChameleonCommunicator {
  _Reader() : super(Logger(level: Level.off));

  _Card? card;
  bool reader = false;
  bool unlocked = false;
  int? pendingBlock;
  final written = <int>[];

  /// 'scan' or 'detect': that call times out once, like a reader that
  /// doesn't answer (sendCmd throws a TimeoutException).
  String? timeoutOnce;

  void _maybeTimeout(String call) {
    if (timeoutOnce == call) {
      timeoutOnce = null;
      throw TimeoutException('Waiting for response');
    }
  }

  @override
  Future<bool> isReaderDeviceMode() async => reader;

  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {
    reader = readerMode;
  }

  @override
  Future<bool> detectMf1Support() async {
    _maybeTimeout('detect');
    return reader && card != null && card!.blocks > 0;
  }

  @override
  Future<CardData?> scan14443aTag() async {
    _maybeTimeout('scan');
    return reader && card != null
        ? CardData(
            uid: Uint8List.fromList(card!.uid),
            atqa: Uint8List.fromList([0x00, 0x04]),
            sak: 0x08,
            ats: Uint8List(0),
          )
        : null;
  }

  @override
  Future<Uint8List> send14ARaw(
    Uint8List data, {
    int respTimeoutMs = 100,
    int? bitLen,
    bool activateRfField = true,
    bool waitResponse = true,
    bool appendCrc = true,
    bool autoSelect = true,
    bool keepRfField = false,
    bool checkResponseCrc = true,
  }) async {
    final ack = Uint8List.fromList([0x0a]);
    final c = card;
    if (!reader || c == null) return Uint8List(0);
    if (data.length == 2 && data[0] == 0x60) {
      // Auth request: a nonce comes back only for a block the card has.
      return data[1] < c.blocks ? Uint8List(4) : Uint8List(0);
    }
    if (bitLen == 7 && data[0] == 0x40) {
      unlocked = c.gen1a && c.blocks > 0;
      return unlocked ? ack : Uint8List(0);
    }
    if (!unlocked) return Uint8List(0);
    if (data.length == 1 && data[0] == 0x43) return ack;
    if (data.length == 2 && data[0] == 0xA0) {
      pendingBlock = data[1];
      return ack;
    }
    if (data.length == 16 && pendingBlock != null) {
      written.add(pendingBlock!);
      pendingBlock = null;
      return ack;
    }
    return Uint8List(0);
  }
}

class _Serial extends AbstractSerial {
  _Serial() : super(log: Logger(level: Level.off)) {
    connected = true;
    device = ChameleonDevice.ultra;
  }
  @override
  bool isManualConnectionSupported() => false;
  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async => true;
  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async => [];
  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async => true;
}

final _gen1a1k = _Card(uid: [0x5E, 0xED, 0x00, 0x04], blocks: 64);
final _gen1a4k = _Card(uid: [0x5E, 0xED, 0x00, 0x04], blocks: 256);
final _ntag = _Card(uid: [4, 1, 2, 3, 4, 5, 6], blocks: 0, gen1a: false);

CardSave _dump(TagType tag, int blocks) => CardSave(
  uid: '5E ED 00 04',
  name: 'Door',
  tag: tag,
  sak: 0x08,
  atqa: Uint8List.fromList([0x00, 0x04]),
  data: List.generate(blocks, (i) => Uint8List(16)..fillRange(0, 16, i)),
);

Future<_Reader> _openWriteCard(WidgetTester tester, CardSave dump) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = SharedPreferencesProvider();
  await prefs.load();
  prefs.setCards([dump]);
  final reader = _Reader();
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: ChameleonGUIState(prefs)
        ..connector = _Serial()
        ..communicator = reader,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WriteCardPage(),
      ),
    ),
  );
  return reader;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder.hitTestable().first);
  await tester.pumpAndSettle();
}

Finder _button(String label) => find.widgetWithText(TextButton, label);

/// Picks the saved card (tapping the suggestion, no Enter), then goes
/// through Next, Next to the write step with Gen1 selected.
Future<void> _pickCardAndGen1(
  WidgetTester tester, {
  bool repickGen1 = false,
}) async {
  await _tap(tester, find.text('Select saved card'));
  await _tap(tester, find.text('Door'));
  await _tap(tester, _button('Next'));
  if (repickGen1) {
    await _tap(tester, find.byType(DropdownButton<AbstractWriteHelper>));
    await _tap(tester, find.text('Gen1'));
  }
  await _tap(tester, _button('Next'));
}

void main() {
  testWidgets('a card put on after picking the dump is written', (
    tester,
  ) async {
    final reader = await _openWriteCard(tester, _dump(TagType.mifare1K, 64));
    await _pickCardAndGen1(tester);

    reader.card = _gen1a1k;
    await _tap(tester, _button('Write data'));

    expect(reader.written, List.generate(64, (i) => i));
    expect(find.text('Card written successfully'), findsOneWidget);
  });

  testWidgets('Gen1 picked from the list writes a whole 4K dump', (
    tester,
  ) async {
    final reader = await _openWriteCard(tester, _dump(TagType.mifare4K, 256));
    reader.card = _gen1a4k;
    await _pickCardAndGen1(tester, repickGen1: true);

    await _tap(tester, _button('Write data'));

    expect(reader.written, List.generate(256, (i) => i));
    expect(find.text('Card written successfully'), findsOneWidget);
  });

  testWidgets('writing to a card that is not MIFARE Classic fails', (
    tester,
  ) async {
    final reader = await _openWriteCard(tester, _dump(TagType.mifare1K, 64));
    await _pickCardAndGen1(tester);

    reader.card = _ntag;
    await _tap(tester, _button('Write data'));
    expect(
      find.textContaining("Your Magic card isn't compatible"),
      findsOneWidget,
    );
    await _tap(tester, find.text('Continue anyway'));

    expect(reader.written, isEmpty);
    expect(find.text('Something went wrong in card writing'), findsOneWidget);
    expect(find.text('Card written successfully'), findsNothing);
  });

  testWidgets('with no card in range it says no card found', (tester) async {
    final reader = await _openWriteCard(tester, _dump(TagType.mifare1K, 64));
    await _pickCardAndGen1(tester);

    await _tap(tester, _button('Write data'));

    expect(
      find.text('No card found. Try to move Chameleon on card'),
      findsOneWidget,
    );
    expect(find.textContaining("isn't compatible"), findsNothing);
    expect(find.text('Continue anyway'), findsNothing);

    reader.card = _gen1a1k;
    await _tap(tester, _button('Write data'));

    expect(reader.written, List.generate(64, (i) => i));
    expect(find.text('Card written successfully'), findsOneWidget);
  });

  for (final (call, retry) in [
    ('scan', 'Write data'),
    ('detect', 'Write again'),
  ]) {
    testWidgets('a reader timeout at the $call fails and can be retried', (
      tester,
    ) async {
      final reader = await _openWriteCard(tester, _dump(TagType.mifare1K, 64));
      reader.card = _gen1a1k;
      await _pickCardAndGen1(tester);

      reader.timeoutOnce = call;
      await _tap(tester, _button('Write data'));

      expect(reader.written, isEmpty);
      expect(find.text('Something went wrong in card writing'), findsOneWidget);

      await _tap(tester, _button(retry));

      expect(reader.written, List.generate(64, (i) => i));
      expect(find.text('Card written successfully'), findsOneWidget);
    });
  }

  testWidgets('a card on the reader the whole time is written', (tester) async {
    final reader = await _openWriteCard(tester, _dump(TagType.mifare1K, 64));
    reader.card = _gen1a1k;
    await _pickCardAndGen1(tester);

    await _tap(tester, _button('Write data'));

    expect(reader.written, List.generate(64, (i) => i));
    expect(find.text('Card written successfully'), findsOneWidget);
  });

  test('Gen2 does not report a write without a MIFARE Classic card', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesProvider();
    await prefs.load();
    final reader = _Reader()
      ..reader = true
      ..card = _ntag;
    final helper = MifareClassicGen2WriteHelper(
      reader,
      recovery: MifareClassicRecovery(
        appState: ChameleonGUIState(prefs),
        update: () {},
        localizations: await AppLocalizations.delegate.load(const Locale('en')),
      ),
    )..vanitySak = false;
    await helper.getCardType();

    expect(helper.type, MifareClassicType.none);
    expect(await helper.writeData(_dump(TagType.mifare1K, 64), (_) {}), false);
  });
}
