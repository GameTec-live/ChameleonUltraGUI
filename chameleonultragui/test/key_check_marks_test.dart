import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long press and drag applies the initial key action in bulk',
      (tester) async {
    final checkMarks =
        List.filled(80, ChameleonKeyCheckmark.none, growable: false);
    final validKeys = List.generate(80, (_) => Uint8List(0), growable: false);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return KeyCheckMarks(
                checkMarks: checkMarks,
                validKeys: validKeys,
                checkmarkCount: 3,
                checkmarkPerRow: 3,
                onCheckmarkChanged: (index, newValue) {
                  setState(() => checkMarks[index] = newValue);
                },
              );
            },
          ),
        ),
      ),
    );

    final firstKey = tester.getCenter(find.byIcon(Icons.close).at(0));
    final secondKey = tester.getCenter(find.byIcon(Icons.close).at(1));
    final gesture = await tester.startGesture(firstKey);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(secondKey);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(checkMarks[0], ChameleonKeyCheckmark.disabled);
    expect(checkMarks[1], ChameleonKeyCheckmark.disabled);
    expect(checkMarks[2], ChameleonKeyCheckmark.none);

    final firstDisabledKey = tester.getCenter(find.byIcon(Icons.cancel).at(0));
    final secondDisabledKey = tester.getCenter(find.byIcon(Icons.cancel).at(1));
    final enableGesture = await tester.startGesture(firstDisabledKey);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await enableGesture.moveTo(secondDisabledKey);
    await tester.pump();
    await enableGesture.up();
    await tester.pump();

    expect(checkMarks[0], ChameleonKeyCheckmark.none);
    expect(checkMarks[1], ChameleonKeyCheckmark.none);
    expect(checkMarks[2], ChameleonKeyCheckmark.none);
  });
}
