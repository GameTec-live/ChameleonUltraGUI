import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/card_auth_key_field.dart';
import 'package:chameleonultragui/gui/component/mifare/classic.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/settings.dart';
import 'package:chameleonultragui/helpers/sl1_card_save.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'classic_coverage_workflows_test.dart' show liveHelper;
import 'sl1_card_workflows_test.dart'
    show appFor, host, SlotRouteProbe, SlotRouteProbeState;
import 'sl1_profile_test.dart' show fixture;
import 'sl1_routes_test.dart' show acquisition, ProfileRouteDevice;

const syntheticSecret = 'FFEEDDCCBBAA99887766554433221100';

Finder authInput() => find.descendant(
  of: find.byType(CardAuthKeyField),
  matching: find.byType(TextFormField),
);

class EmptySlotSettings extends SlotSettings {
  const EmptySlotSettings({super.key}) : super(slot: 2, refresh: _refresh);
  static void _refresh() {}
  @override
  SlotSettingsState createState() => _EmptySlotSettingsState();
}

class _EmptySlotSettingsState extends SlotSettingsState {
  @override
  void initState() {
    super.initState();
    names.hf = 'Empty';
    names.lf = 'Empty';
  }
}

void main() {
  testWidgets('an empty slot still exposes optional staged-upload recovery', (
    tester,
  ) async {
    final app = (await appFor(sl1ToCard(fixture())))
      ..communicator = ProfileRouteDevice();
    await tester.pumpWidget(host(app, const EmptySlotSettings()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('CardAuth diagnostics'));
    await tester.tap(find.text('CardAuth diagnostics'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancel staged upload'));
    await tester.tap(find.text('Cancel staged upload'));
    await tester.pumpAndSettle();
    expect((app.communicator as ProfileRouteDevice).calls, contains(4049));
  });

  for (final (detected, withAuth) in [
    (false, false),
    (true, true),
    (true, false),
  ]) {
    testWidgets(
      'read → save → reload → slot, detected=$detected, key=$withAuth, no file import',
      (tester) async {
        final device = ProfileRouteDevice();
        final (recovery, scanned) = await acquisition(device);
        await recovery.dumpData();
        final app = (await appFor(scanned))..communicator = device;
        app.sharedPreferencesProvider.setCards([]);
        final read = liveHelper(
          GlobalKey<CardReaderState>(),
          recovery,
          scanned,
        );
        read.mfcInfo.sl1CardAuthDetected = detected;
        await tester.pumpWidget(
          host(app, Scaffold(body: SingleChildScrollView(child: read))),
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final name = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            )
            .first;
        await tester.enterText(name, 'Read on phone');
        if (detected) {
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: find.byType(CardAuthKeyField),
                    matching: find.byType(EditableText),
                  ),
                )
                .obscureText,
            isTrue,
          );
        }
        if (!detected) expect(authInput(), findsNothing);
        if (withAuth) {
          await tester.enterText(authInput(), 'invalid');
          await tester.tap(find.text('Save').last);
          await tester.pumpAndSettle();
          expect(find.text('Enter exactly 32 hex characters'), findsOneWidget);
          expect(app.sharedPreferencesProvider.getCards(), isEmpty);
          await tester.enterText(authInput(), syntheticSecret.toLowerCase());
        }
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);

        final reloaded = SharedPreferencesProvider();
        await reloaded.load();
        var saved = reloaded.getCards().single;
        expect(saved.name, 'Read on phone');
        expect(saved.extraData.sl1CardAuthDetected, detected);
        expect(
          saved.sl1Profile!.json['classic'],
          recovery.profileFor(saved).json['classic'],
        );
        final auth = saved.sl1Profile!.json['cardAuth'];
        if (withAuth) {
          expect(auth['key'], syntheticSecret);
          expect(auth['enabled'], isTrue);
          expect(auth['verification']['status'], 'provided');
        } else {
          expect(auth, isNull);
        }

        if (detected && !withAuth) {
          await tester.pumpWidget(
            host(
              app,
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => CardEditMenu(tagSave: saved),
                  ),
                  child: const Text('Edit detected card'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Edit detected card'));
          await tester.pumpAndSettle();
          expect(authInput(), findsOneWidget);
          await tester.enterText(
            find.byType(TextFormField).first,
            'Read renamed',
          );
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          saved = app.sharedPreferencesProvider.getCards().single;
          expect(saved.extraData.sl1CardAuthDetected, isTrue);
          expect(saved.sl1Profile!.json['cardAuth'], isNull);
        }

        final slot = GlobalKey<SlotRouteProbeState>();
        await tester.pumpWidget(host(app, SlotRouteProbe(key: slot)));
        slot.currentState!.gridPosition = 1;
        await slot.currentState!.onTap(
          saved,
          (_, _) {},
          await AppLocalizations.delegate.load(const Locale('en')),
        );
        await tester.pumpAndSettle();
        final begin = device.calls.indexOf(4046);
        expect(begin, greaterThanOrEqualTo(0));
        expect(device.payloads[begin][1], 1);
        expect(device.payloads[begin][16], withAuth ? 1 : 0);
        expect(device.payloads[begin][17], withAuth ? 1 : 0);
        if (withAuth) {
          expect(
            device.payloads[begin].sublist(20, 36),
            List.generate(
              16,
              (i) => int.parse(
                syntheticSecret.substring(i * 2, i * 2 + 2),
                radix: 16,
              ),
            ),
          );
        }
        expect(device.calls.where((c) => c == 4048), hasLength(1));
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }

  testWidgets('cancel read-save form leaves the library unchanged', (
    tester,
  ) async {
    final (recovery, card) = await acquisition(ProfileRouteDevice());
    await recovery.dumpData();
    final app = await appFor(card);
    final original = app.sharedPreferencesProvider.getCards().single.toJson();
    await tester.pumpWidget(
      host(
        app,
        Scaffold(
          body: SingleChildScrollView(
            child: liveHelper(GlobalKey<CardReaderState>(), recovery, card),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(authInput(), findsNothing);
    await tester.tap(find.text('Additional settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add CardAuth key'));
    await tester.pumpAndSettle();
    await tester.enterText(authInput(), syntheticSecret);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.sharedPreferencesProvider.getCards().single.toJson(), original);
  });

  for (final action in ['keep disabled', 'replace', 'clear', 'cancel']) {
    testWidgets('ordinary card edit can $action AUTH9004', (tester) async {
      final card = sl1ToCard(fixture());
      card.sl1Profile!.json['cardAuth']['enabled'] = false;
      final app = await appFor(card);
      final original = card.toJson();
      await tester.pumpWidget(
        host(
          app,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => CardEditMenu(tagSave: card),
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      if (action != 'keep disabled') {
        await tester.enterText(
          authInput(),
          action == 'clear' ? '' : syntheticSecret,
        );
      }
      await tester.tap(find.text(action == 'cancel' ? 'Cancel' : 'Save'));
      await tester.pumpAndSettle();
      final saved = app.sharedPreferencesProvider.getCards().single;
      if (action == 'cancel') {
        expect(saved.toJson(), original);
      } else if (action == 'clear') {
        expect(saved.sl1Profile!.json['cardAuth'], isNull);
      } else {
        expect(
          saved.sl1Profile!.json['cardAuth']['enabled'],
          action == 'replace',
        );
        expect(
          saved.sl1Profile!.json['cardAuth']['key'],
          action == 'replace'
              ? syntheticSecret
              : card.sl1Profile!.json['cardAuth']['key'],
        );
      }
      expect(
        saved.sl1Profile!.json['classic'],
        card.sl1Profile!.json['classic'],
      );
    });
  }
}
