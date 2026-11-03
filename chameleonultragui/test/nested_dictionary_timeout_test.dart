import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'batch_key_check_test.dart' show TestCommunicator, reply, result;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final changedCard in [false, true]) {
    test(
      'nested timeout ${changedCard ? 'rejects a changed card' : 'disables nested checks and continues ordinary checking'}',
      () async {
        var captures = 0;
        final attempts = <int>[];
        final device = TestCommunicator((cmd, data, timeout) {
          switch (cmd) {
            case ChameleonCommand.scan14ATag:
              return reply(cmd, [
                4,
                changedCard && captures > 0 ? 9 : 1,
                2,
                3,
                4,
                4,
                0,
                8,
                0,
              ]);
            case ChameleonCommand.mf1NTLevelDetect:
              return reply(cmd, [1]);
            case ChameleonCommand.mf1NestedAcquire:
              captures++;
              throw TimeoutException('Waiting for response for command 2006');
            case ChameleonCommand.mf1CheckKey:
              attempts.add(data!.last);
              return reply(cmd, [], status: data.last == 100 ? 0 : 6);
            case ChameleonCommand.mf1CheckKeysOfSectors:
              return reply(cmd, result({}));
            default:
              throw StateError('Unexpected command $cmd');
          }
        });
        final state = ChameleonGUIState(SharedPreferencesProvider())
          ..communicator = device
          ..log = Logger(level: Level.off);
        final check = MifareClassicRecovery(
          appState: state,
          update: () {},
          localizations: await AppLocalizations.delegate.load(
            const Locale('en'),
          ),
          mifareClassicType: MifareClassicType.m1k,
          selectedDictionary: Dictionary(
            keys: [
              for (var i = 0; i <= 100; i++)
                Uint8List.fromList([0, 0, 0, 0, 0, i]),
            ],
          ),
        );
        check.checkMarks.fillRange(0, 80, ChameleonKeyCheckmark.disabled);
        check.checkMarks[0] = ChameleonKeyCheckmark.found;
        check.validKeys[0] = Uint8List(6);
        check.checkMarks[40] = ChameleonKeyCheckmark.none;
        check.checkMarks[1] = ChameleonKeyCheckmark.none;

        if (changedCard) {
          await expectLater(
            check.checkKeys(skipDefaultDictionary: true),
            throwsStateError,
          );
          expect(attempts, isEmpty);
          expect(check.allKeysExists, false);
        } else {
          await check.checkKeys(skipDefaultDictionary: true);
          expect(attempts, [
            for (var pass = 0; pass < 2; pass++)
              ...List.generate(101, (i) => i),
          ]);
          expect(check.validKeys[40], [0, 0, 0, 0, 0, 100]);
          expect(check.validKeys[1], [0, 0, 0, 0, 0, 100]);
          expect(check.allKeysExists, true);
        }
        expect(captures, 1);
        expect(
          check.checkMarks,
          isNot(contains(ChameleonKeyCheckmark.checking)),
        );
      },
    );
  }
}
