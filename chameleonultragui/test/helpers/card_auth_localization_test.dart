// Overrides retain the generated AppLocalizations getter names.
// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations_en.dart';
import 'package:chameleonultragui/gui/component/card_auth_key_field.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/sl1_profile_status.dart';
import 'package:chameleonultragui/helpers/sl1_profile_uploader.dart';

class TranslatedControls extends AppLocalizationsEn {
  @override
  String get additional_settings => 'Localized settings';
  @override
  String get card_auth_add_key => 'Localized add key';
  @override
  String get card_auth_key_label => 'Localized key';
  @override
  String get card_auth_key_help => 'Localized help';
  @override
  String get card_auth_key_visibility => 'Localized visibility';
  @override
  String get card_auth_invalid_key => 'Localized invalid key';
  @override
  String get card_auth_configured => 'Localized configured';
  @override
  String get card_auth_recovery_hint => 'Localized recovery';
  @override
  String get card_auth_save_staged => 'Localized save stage';
  @override
  String get close => 'Localized close';
}

class TestLocalizations extends LocalizationsDelegate<AppLocalizations> {
  const TestLocalizations();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';
  @override
  Future<AppLocalizations> load(Locale locale) async => TranslatedControls();
  @override
  bool shouldReload(TestLocalizations old) => false;
}

Widget localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: [
    const TestLocalizations(),
    ...AppLocalizations.localizationsDelegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'manual CardAuth field uses current localization and validation',
    (tester) async {
      final controller = TextEditingController(text: 'invalid');
      addTearDown(controller.dispose);
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        localized(
          Form(
            key: key,
            child: CardAuthKeyField(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Localized key'), findsOneWidget);
      expect(find.text('Localized help'), findsOneWidget);
      expect(find.byTooltip('Localized visibility'), findsOneWidget);
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Localized invalid key'), findsOneWidget);
    },
  );

  testWidgets('manual reserve uses localized disclosure and add action', (
    tester,
  ) async {
    await tester.pumpWidget(
      localized(const CardAuthKeyField(initiallyVisible: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Localized settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Localized add key'));
    await tester.pumpAndSettle();
    expect(find.text('Localized key'), findsOneWidget);
  });

  testWidgets('diagnostics uses current localization for status and recovery', (
    tester,
  ) async {
    final uploader = Sl1Uploader(
      (_, payload) async => Uint8List.fromList([
        1,
        payload[1],
        0x48,
        3,
        0xE8,
        0,
        0,
        0,
        0,
        20,
        0,
        20,
        0,
        0,
      ]),
      () async => [4045],
    );
    await tester.pumpWidget(
      localized(Sl1SlotDialog(slot: 2, uploader: uploader)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Localized configured'), findsOneWidget);
    expect(find.textContaining('Localized recovery'), findsOneWidget);
    expect(find.text('Localized save stage'), findsOneWidget);
    expect(find.text('Localized close'), findsOneWidget);
  });
}
