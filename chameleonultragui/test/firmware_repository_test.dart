import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/firmware_repository_input.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('validateRepository accepts only owner/name', () {
    for (var valid in [
      defaultFirmwareRepository,
      "some-one/Chameleon.Ultra_2",
    ]) {
      expect(validateRepository(valid, l10n), isNull, reason: valid);
    }

    for (var invalid in [
      null,
      "",
      "owner",
      "owner/",
      "/name",
      "owner/name/extra",
      "https://github.com/owner/name",
      "some one/name",
    ]) {
      expect(validateRepository(invalid, l10n), l10n.invalid_repository,
          reason: invalid);
    }
  });

  group('FirmwareRepositoryInput', () {
    Future<List<String>> pumpInput(WidgetTester tester) async {
      final saved = <String>[];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FirmwareRepositoryInput(
              initialValue: defaultFirmwareRepository, onSave: saved.add),
        ),
      ));
      return saved;
    }

    VoidCallback? onPressed(WidgetTester tester, String label) {
      final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      return tester.widget<ButtonStyleButton>(button).onPressed;
    }

    testWidgets('saves the trimmed value and resets to the default',
        (tester) async {
      final saved = await pumpInput(tester);
      expect(onPressed(tester, l10n.save), isNull);
      expect(onPressed(tester, l10n.def), isNull);

      await tester.enterText(
          find.byType(TextFormField), "  someone/ChameleonUltra ");
      await tester.pump();
      await tester.tap(find.text(l10n.save));
      await tester.pump();

      expect(saved, ["someone/ChameleonUltra"]);
      expect(onPressed(tester, l10n.save), isNull);

      await tester.tap(find.text(l10n.def));
      await tester.pump();

      expect(saved, ["someone/ChameleonUltra", defaultFirmwareRepository]);
      expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          defaultFirmwareRepository);
    });

    testWidgets('does not save a value that is not owner/name',
        (tester) async {
      final saved = await pumpInput(tester);

      await tester.enterText(find.byType(TextFormField), "not a repository");
      await tester.pump();
      await tester.tap(find.text(l10n.save));
      await tester.pump();

      expect(saved, isEmpty);
      expect(find.text(l10n.invalid_repository), findsOneWidget);
    });
  });
}
