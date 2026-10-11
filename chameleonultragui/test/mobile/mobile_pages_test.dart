import 'dart:typed_data';

import 'package:chameleonultragui/gui/mobile/pages/library_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/slots_page.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

CardSave card(String name, TagType tag, {String uid = 'DEADBEEF'}) => CardSave(
  uid: uid,
  sak: 0x08,
  atqa: Uint8List.fromList([0x00, 0x04]),
  name: name,
  tag: tag,
  data: [],
);

void main() {
  group('library', () {
    Future<ChameleonGUIState> libraryState() async {
      final appState = await createAppState();
      appState.sharedPreferencesProvider.setCards([
        card('Office badge', TagType.mifare1K),
        card('Gym tag', TagType.em410X, uid: '0102030405'),
        card('Garage', TagType.ntag215, uid: '04AABBCCDDEE80'),
      ]);
      return appState;
    }

    testWidgets('lists, searches and filters saved cards', (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await libraryState();

      await tester.pumpWidget(buildMobileApp(appState));
      await tester.tap(find.text('Cards'));
      await tester.pump();

      expect(find.text('Office badge'), findsOneWidget);
      expect(find.text('Gym tag'), findsOneWidget);
      expect(find.text('Garage'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'gym');
      await tester.pump();
      expect(find.text('Gym tag'), findsOneWidget);
      expect(find.text('Office badge'), findsNothing);

      await tester.enterText(find.byType(SearchBar), 'nothing like this');
      await tester.pump();
      expect(find.text('No cards match your search'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), '');
      await tester.tap(find.widgetWithText(ChoiceChip, 'LF'));
      await tester.pump();
      expect(find.text('Gym tag'), findsOneWidget);
      expect(find.text('Office badge'), findsNothing);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('delete asks for confirmation and removes the card', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await libraryState();

      await tester.pumpWidget(buildMobileApp(appState));
      await tester.tap(find.text('Cards'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm deletion'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(appState.sharedPreferencesProvider.getCards().length, 2);
      await unmount(tester);
    });

    testWidgets('pick mode returns the tapped card', (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await libraryState();
      CardSave? picked;

      await tester.pumpWidget(buildMobileApp(appState));
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator
          .push<CardSave>(
            MaterialPageRoute(
              builder: (_) => const MobileLibraryPage(pickMode: true),
            ),
          )
          .then((card) => picked = card);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await tester.tap(find.text('Gym tag'));
      await tester.pumpAndSettle();

      expect(picked?.name, 'Gym tag');
      await unmount(tester);
    });
  });

  group('slots', () {
    testWidgets('slot manager lists eight slots and opens actions', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final appState = await createAppState();

      await tester.pumpWidget(buildMobileApp(appState));
      await connectEmulator(tester, appState);

      await tester.tap(find.widgetWithText(FilledButton, 'Slots'));
      await tester.pumpAndSettle();

      expect(find.byType(MobileSlotsPage), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Slot 1'));
      await tester.pumpAndSettle();
      expect(find.text('Load into slot'), findsOneWidget);
      expect(find.text('Slot Settings'), findsOneWidget);
      expect(find.text('Activate'), findsOneWidget);

      await unmount(tester);
    });
  });
}
