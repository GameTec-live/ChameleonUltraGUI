import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/helpers/recovery_operation.dart';
import 'package:logger/logger.dart';
import 'package:chameleonultragui/plugins/api.dart';
import 'package:chameleonultragui/plugins/plugin.dart';
import 'package:chameleonultragui/plugins/runtime.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ChameleonGUIState app;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    app = ChameleonGUIState(preferences);
  });

  Future<PluginApi> host(WidgetTester tester, Plugin plugin) async {
    late PluginApi api;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            api = PluginApi(context, app, plugin);
            return const Scaffold();
          },
        ),
      ),
    );
    return api;
  }

  Future<void> run(WidgetTester tester, String code) async {
    final plugin = Plugin(name: 'Extension tests', code: code);
    final api = await host(tester, plugin);
    await tester.runAsync(
      () => PluginRuntime().run(plugin, api.methods.keys, api.call),
    );
  }

  testWidgets('Lua saved-data CRUD and folder imports preserve integrity', (
    tester,
  ) async {
    await run(tester, '''
      local cards, folders = chameleon.cards, chameleon.cardFolders
      local root = folders.save({name = 'Root'})
      local child = folders.save({name = 'Child', parentId = root})
      local id = cards.save({name = 'Original', uid = '01020304', tag = 1001})
      assert(cards.move(id, child))
      assert(cards.get(id).folderId == child)
      assert(not pcall(folders.save, {id = root, name = 'Root', parentId = child}))
      assert(not pcall(cards.move, id, 'missing-folder'))
      local bundle = folders.export(root)
      local imported = folders.import(bundle)
      assert(imported ~= root)
      assert(#folders.list() == 4 and #cards.list() == 2)
      local detached = cards.get(id)
      detached.id = nil
      detached.folderId = nil
      detached.name = 'Duplicate'
      local duplicate = cards.save(detached)
      assert(duplicate ~= id and cards.get(duplicate).folderId == nil)
      local json = cards.encode(cards.get(duplicate))
      assert(cards.decode(json).uid == '01020304')
      assert(#cards.encode(cards.get(duplicate), 'bin') == 1024)
      assert(folders.delete(root))
      assert(cards.get(id) == nil and #cards.list() == 2)
      assert(cards.delete(duplicate) and not cards.delete(duplicate))
      assert(folders.delete(imported))
      assert(#cards.list() == 0 and #folders.list() == 0)

      local dictionaries, df = chameleon.dictionaries, chameleon.dictionaryFolders
      local folder = df.save({name = 'Keys'})
      local dictionary = dictionaries.decode('FFFFFFFFFFFF\\nA0A1A2A3A4A5', 'Example')
      dictionary.folderId = folder
      local keyId = dictionaries.save(dictionary)
      assert(dictionaries.get(keyId).keyLength == 12)
      assert(dictionaries.encode(dictionary) == 'FFFFFFFFFFFF\\nA0A1A2A3A4A5\\n')
      assert(not pcall(dictionaries.save, {name = 'Invalid', keys = {{256}}}))
      local copy = df.import(df.export(folder))
      assert(copy ~= folder and #dictionaries.list() == 2)
      assert(dictionaries.move(keyId))
      assert(df.delete(folder))
      assert(dictionaries.get(keyId).folderId == nil)
      assert(dictionaries.delete(keyId))
      assert(df.delete(copy) and #dictionaries.list() == 0)
    ''');
  });

  testWidgets(
    'writing an unprotected NTAG without a key uses the no-key flow',
    (tester) async {
      final device = _UnprotectedTag();
      app.connector = _PreferenceSerial();
      app.communicator = device;
      app.sharedPreferencesProvider.setCards([
        CardSave(
          name: 'NTAG',
          uid: '01020304',
          tag: TagType.ntag213,
          data: [
            Uint8List.fromList([1, 2, 3, 4]),
          ],
        ),
      ]);
      final plugin = Plugin(
        name: 'Write',
        code: 'assert(chameleon.cards.write(chameleon.cards.list()[1]))',
      );
      late PluginApi api;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              api = PluginApi(context, app, plugin);
              return const Scaffold();
            },
          ),
        ),
      );
      await tester.runAsync(
        () => PluginRuntime().run(plugin, api.methods.keys, api.call),
      );
      expect(device.frames, [
        [0xA2, 0, 1, 2, 3, 4],
      ]);
    },
  );

  testWidgets(
    'loading EV1 dumps initializes a 2K emulator and preserves all 72 blocks',
    (tester) async {
      final device = _SlotDevice();
      app.connector = _PreferenceSerial();
      app.communicator = device;
      final card = CardSave(
        name: 'EV1',
        uid: '01020304',
        tag: TagType.mifare1K,
        data: List.generate(
          72,
          (index) => Uint8List(16)..fillRange(0, 16, index),
        ),
      );
      final api = await host(tester, Plugin(name: 'Load EV1', code: ''));
      await tester.runAsync(
        () => api.call('slots.load', [0, jsonDecode(card.toJson())]),
      );
      expect(device.types, [TagType.mifare2K]);
      expect(device.defaults, [TagType.mifare2K]);
      for (var index = 0; index < 72; index++) {
        expect(
          device.blocks[index],
          List.filled(16, index),
          reason: 'block $index',
        );
      }
      expect(card.tag, TagType.mifare1K);
    },
  );

  testWidgets('invalid folder bundle leaves saved data untouched', (
    tester,
  ) async {
    final api = await host(tester, Plugin(name: 'Import', code: ''));
    final root = await api.call('cardFolders.save', [
      {'name': 'Existing'},
    ]);
    final bundle = {
      'format': 'chameleon-ultra-gui-folder',
      'version': 1,
      'rootFolderId': 'one',
      'folders': [
        {'id': 'one', 'name': 'One'},
        {'id': 'two', 'name': 'Two', 'parentId': 'two'},
      ],
      'cards': [],
    };
    await expectLater(
      api.call('cardFolders.import', [jsonEncode(bundle)]),
      throwsArgumentError,
    );
    expect(
      (await api.call('cardFolders.list', []) as List).single,
      containsPair('id', root),
    );
    expect(await api.call('cards.list', []), isEmpty);
  });

  testWidgets(
    'settings patches validate all fields and persist supported locale tags',
    (tester) async {
      final api = await host(tester, Plugin(name: 'Settings', code: ''));
      var notifications = 0;
      app.addListener(() => notifications++);
      await run(tester, '''
      local settings = chameleon.settings
      local before = settings.get()
      assert(not pcall(settings.update, {theme = 'dark', language = 'invalid'}))
      assert(settings.get().theme == before.theme)
      assert(not pcall(settings.update, {themeColor = 8}))
      assert(not pcall(settings.update, {unexpected = true}))
      local current = settings.update({theme = 'dark', language = 'pt-BR', themeColor = 2,
        sidebar = 'collapsed', autoScan = false, autoConnect = true, confirmDelete = false,
        debugMode = true, debugLogging = true})
      assert(current.language == 'pt-BR' and current.theme == 'dark')
      assert(current.themeColor == 2 and current.sidebar == 'collapsed')
      assert(not current.autoScan and current.autoConnect and not current.confirmDelete)
      assert(current.debugMode and current.debugLogging)
      assert(#settings.options().language > 1)
    ''');
      await tester.pump(const Duration(seconds: 1));
      expect(
        app.sharedPreferencesProvider.getLocale().toLanguageTag(),
        'pt-BR',
      );
      expect(app.sharedPreferencesProvider.getTheme(), ThemeMode.dark);
      expect(app.sharedPreferencesProvider.getSideBarAutoExpansion(), false);
      expect(app.sharedPreferencesProvider.getSideBarExpanded(), false);
      expect(app.log, isNotNull);
      expect(notifications, greaterThan(0));
      expect((await api.call('settings.get', []) as Map)['debugLogging'], true);
    },
  );

  testWidgets(
    'offline native recovery accepts captures and exact 64-bit hex fields',
    (tester) async {
      await run(tester, '''
      local recovery = chameleon.recovery
      local keys = recovery.nested({uid = 2374329723, distance = 613,
        nt0 = 1999585272, nt0Enc = 3173333529, par0 = 3,
        nt1 = 128306861, nt1Enc = 2363514210, par1 = 7})
      local found = false
      for _, key in ipairs(keys) do if key == 0xFFFFFFFFFFFF then found = true end end
      assert(found)
      local darkside = recovery.darkside({uid = 2374329723, items = {
        {nt1 = 913032415, ks1 = '0302090B01010308', par = '0', nr = 0, ar = 0},
        {nt1 = 913032415, ks1 = '0E050F0E0B06020B', par = '0', nr = 1, ar = 0}
      }})
      assert(#darkside > 0)
      local noMatch = recovery.mfkey32({uid = 0, nt0 = 0, nt1 = 0,
        nr0Enc = 0, ar0Enc = 0, nr1Enc = 0, ar1Enc = 1})
      assert(#noMatch == 0)
      assert(not pcall(recovery.hardNested, {1, 2, 3}))
      assert(not pcall(recovery.mfkey32, {uid = -1}))
      assert(not pcall(recovery.darkside, {uid = 1, items = {
        {nt1 = 1, ks1 = 9007199254740992, par = 0, nr = 0, ar = 0}
      }}))
    ''');
    },
  );

  testWidgets('changing demo mode disconnects, appearance changes do not', (
    tester,
  ) async {
    final serial = _PreferenceSerial();
    app.connector = serial;
    final api = await host(tester, Plugin(name: 'Preferences', code: ''));
    await api.call('settings.update', [
      {'theme': 'dark'},
    ]);
    expect(serial.disconnects, 0);
    await api.call('settings.update', [
      {'emulatedDevice': true},
    ]);
    expect(serial.disconnects, 1);
    expect(app.connector, isNull);
    expect(app.sharedPreferencesProvider.isEmulatedChameleon(), true);
  });

  testWidgets('cancelled standalone recovery releases the native queue', (
    tester,
  ) async {
    final api = await host(tester, Plugin(name: 'Cancelled search', code: ''));
    final capture = {
      'uid': 2374329723,
      'distance': 613,
      'nt0': 1999585272,
      'nt0Enc': 3173333529,
      'par0': 3,
      'nt1': 128306861,
      'nt1Enc': 2363514210,
      'par1': 7,
    };
    await tester.runAsync(() async {
      final running = api.call('recovery.nested', [capture]);
      api.cancel();
      await expectLater(running, throwsA(isA<RecoveryCancelled>()));
    });
    final retry = await host(tester, Plugin(name: 'Retry', code: ''));
    final result = await tester.runAsync(
      () => retry.call('recovery.nested', [capture]),
    );
    expect(result, contains(0xFFFFFFFFFFFF));
  });

  testWidgets('documented examples import and execute with the actual APIs', (
    tester,
  ) async {
    final directory = Directory('../docs/plugins/examples');
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.plugin.json'))
        .toList();
    expect(files, hasLength(5));
    for (final file in files) {
      final plugin = await Plugin.decode(
        file.readAsStringSync(),
        freshId: true,
      );
      final api = await host(tester, plugin);
      final messages = <Object?>[];
      await tester.runAsync(
        () =>
            PluginRuntime().run(plugin, api.methods.keys, (method, args) async {
              if (method == 'ui.info' || method == 'ui.snackbar') {
                messages.add(args.single);
                return null;
              }
              if (method == 'ui.input') return 'de';
              return api.call(method, args);
            }),
      );
      if (!file.path.contains('choose-language')) expect(messages, isNotEmpty);
    }
    expect(
      app.sharedPreferencesProvider.getDictionaries().single.keys,
      hasLength(2),
    );
    expect(app.sharedPreferencesProvider.getLocaleString(), 'de');
    expect(app.sharedPreferencesProvider.getTheme(), ThemeMode.dark);
  });
}

class _PreferenceSerial extends EmulatorSerial {
  int disconnects = 0;
  _PreferenceSerial() : super(log: Logger(level: Level.off)) {
    connected = true;
  }

  @override
  Future<bool> performDisconnect() async {
    disconnects++;
    return super.performDisconnect();
  }
}

class _UnprotectedTag extends ChameleonCommunicator {
  _UnprotectedTag() : super(Logger(level: Level.off));
  final frames = <List<int>>[];
  @override
  Future<bool> isReaderDeviceMode() async => true;
  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {}
  @override
  Future<CardData?> scan14443aTag() async => CardData(
    uid: Uint8List.fromList([1, 2, 3, 4]),
    sak: 0,
    atqa: Uint8List(2),
    ats: Uint8List(0),
  );
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
    frames.add(data.toList());
    return Uint8List.fromList([0x0A]);
  }
}

class _SlotDevice extends ChameleonCommunicator {
  _SlotDevice() : super(Logger(level: Level.off));
  final types = <TagType>[];
  final defaults = <TagType>[];
  final blocks = <int, List<int>>{};
  @override
  Future<void> setReaderDeviceMode(bool readerMode) async {}
  @override
  Future<void> enableSlot(
    int slot,
    TagFrequency frequency,
    bool status,
  ) async {}
  @override
  Future<void> activateSlot(int slot) async {}
  @override
  Future<void> setSlotType(int slot, TagType type) async {
    types.add(type);
  }

  @override
  Future<void> setDefaultDataToSlot(int slot, TagType type) async {
    defaults.add(type);
  }

  @override
  Future<void> setMf1AntiCollision(CardData card) async {}
  @override
  Future<void> setMf1BlockData(int startBlock, Uint8List data) async {
    for (var offset = 0; offset < data.length; offset += 16) {
      blocks[startBlock + offset ~/ 16] = data.sublist(offset, offset + 16);
    }
  }

  @override
  Future<void> setSlotTagName(
    int index,
    String name,
    TagFrequency frequency,
  ) async {}
  @override
  Future<void> saveSlotData() async {}
}
