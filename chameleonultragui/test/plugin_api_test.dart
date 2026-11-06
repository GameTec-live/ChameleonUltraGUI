// Match the generated localization getter names in the test translations.
// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:chameleonultragui/gui/page/plugins.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/plugins/api.dart';
import 'package:chameleonultragui/plugins/plugin.dart';
import 'package:chameleonultragui/plugins/runtime.dart';
import 'package:chameleonultragui/plugins/store.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/foundation.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations_en.dart';
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

  testWidgets('Lua can round trip a saved card with empty arrays and Unicode', (
    tester,
  ) async {
    late PluginApi api;
    final plugin = Plugin(
      name: 'Card tool',
      code: '''
      local card = chameleon.cards.list()[1]
      assert(card.name == 'Original')
      card.name = '世界'
      chameleon.cards.save(card)
      assert(chameleon.cards.list()[1].name == '世界')
      assert(chameleon.device.connected() == false)
      assert(chameleon.device.enums().commands.getAppVersion ~= nil)
    ''',
    );
    app.sharedPreferencesProvider.setCards([
      CardSave(name: 'Original', uid: '01020304', tag: TagType.mifare1K),
    ]);
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
    await tester.runAsync(
      () => PluginRuntime().run(plugin, api.methods.keys, api.call),
    );
    expect(app.sharedPreferencesProvider.getCards().single.name, '世界');
  });

  testWidgets(
    'input identifies plugin, validates numbers and returns cancellation',
    (tester) async {
      late PluginApi api;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              api = PluginApi(context, app, Plugin(name: 'My tool', code: ''));
              return const Scaffold();
            },
          ),
        ),
      );
      final result = api.call('ui.input', [
        'How many?',
        {'type': 'number'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('My tool — Input'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'OK'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '12.5');
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await result, 12.5);

      final cancelled = api.call('ui.input', [
        'Continue?',
        {'type': 'boolean'},
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await cancelled, isNull);
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'choice input honors a valid default and falls back for an invalid one',
    (tester) async {
      late PluginApi api;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              api = PluginApi(context, app, Plugin(name: 'Choice', code: ''));
              return const Scaffold();
            },
          ),
        ),
      );
      for (final initial in ['second', 'missing']) {
        final result = api.call('ui.input', [
          'Choose',
          {
            'type': 'choice',
            'choices': ['first', 'second'],
            'default': initial,
          },
        ]);
        await tester.pumpAndSettle();
        final expected = initial == 'second' ? 'second' : 'first';
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byType(DropdownButton<String>),
              )
              .value,
          expected,
        );
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(await result, expected);
        await tester.pump(const Duration(seconds: 1));
      }
    },
  );

  testWidgets('failed plugin loads keep stored entries and disable mutations', (
    tester,
  ) async {
    final saved = [
      jsonEncode(Plugin(name: 'Preserved', code: '').toJson()),
      '{broken',
    ];
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('plugins_v1', saved);
    await tester.pumpWidget(const MaterialApp(home: PluginsPage()));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Create plugin',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Import plugin',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(preferences.getStringList('plugins_v1'), saved);
  });

  testWidgets('create editor persists metadata, code and resources', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PluginsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create plugin'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Example');
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'A test plugin',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Resources (JSON object of key: text)'),
      '{"module":"return 42"}',
    );
    await tester.ensureVisible(find.byTooltip('Pick a color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pick a color'));
    await tester.pumpAndSettle();
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(Colors.blue);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Example'), findsOneWidget);
    final saved = (await PluginStore().load()).single;
    expect(saved.description, 'A test plugin');
    expect(saved.color, Colors.blue.toARGB32());
    expect(saved.resources, {'module': 'return 42'});
    expect(saved.code, contains('chameleon.ui.info'));
  });
  testWidgets(
    'plugin UI and isolated diagnostics use the selected translations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            _PluginTranslationsDelegate(),
            ...AppLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PluginsPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Localized import'), findsOneWidget);
      await tester.tap(find.byTooltip('Localized create'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Lua code'))
            .controller!
            .text,
        contains('Localized greeting'),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Localized invalid name'), findsOneWidget);

      final messages = <String>[];
      await tester.runAsync(
        () => PluginRuntime().run(
          Plugin(
            name: 'Translations',
            code: '''
        local ok, message = pcall(chameleon.resources.get, 'missing')
        assert(not ok)
        chameleon.ui.info(message)
      ''',
          ),
          ['ui.info'],
          (_, args) async {
            messages.add(args.single as String);
            return null;
          },
          localizations: _PluginTranslations(),
        ),
      );
      expect(messages.single, contains('Localized missing resource: missing'));
    },
  );
}

class _PluginTranslations extends AppLocalizationsEn {
  @override
  String get cancel => 'Localized cancel';
  @override
  String get plugin_dialog_input => 'Localized input';
  @override
  String plugin_dialog_title(Object kind, Object name) => '$kind :: $name';
  @override
  String get plugin_import => 'Localized import';
  @override
  String get plugin_create => 'Localized create';
  @override
  String get plugin_default_greeting => 'Localized greeting';
  @override
  String get plugin_error_name => 'Localized invalid name';
  @override
  String plugin_error_resource(Object key) =>
      'Localized missing resource: $key';
}

class _PluginTranslationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _PluginTranslationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(_PluginTranslations());
  @override
  bool shouldReload(_PluginTranslationsDelegate old) => false;
}
