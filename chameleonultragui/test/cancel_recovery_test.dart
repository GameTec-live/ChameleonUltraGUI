import 'dart:async';
import 'dart:typed_data';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:logger/logger.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/cancel_recovery.dart';
import 'package:chameleonultragui/helpers/recovery_operation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DetectionCommunicator extends ChameleonCommunicator {
  _DetectionCommunicator() : super(Logger());
  final response = Completer<ChameleonMessage>();
  int pages = 0;

  @override
  Future<ChameleonMessage?> sendCmd(
    ChameleonCommand cmd, {
    Uint8List? data,
    Duration timeout = const Duration(seconds: 5),
    bool skipReceive = false,
    bool firstRun = false,
  }) {
    expect(cmd, ChameleonCommand.mf1GetDetectionResult);
    pages++;
    return response.future;
  }
}

void main() {
  test('cancelled detection fetch awaits the active page and requests no more',
      () async {
    final communicator = _DetectionCommunicator();
    final operation = RecoveryOperation();
    final work = operation.run(() async {
      await operation.wait(communicator.getMf1DetectionResult(2,
          checkCancelled: operation.checkCancelled));
    });
    expect(communicator.pages, 1);
    operation.cancel();
    expect(operation.isRunning, isTrue);
    communicator.response.complete(ChameleonMessage(
      command: ChameleonCommand.mf1GetDetectionResult.value,
      status: 0,
      data: Uint8List(18),
    ));
    await work;
    expect(communicator.pages, 1);
    expect(operation.wasCancelled, isTrue);
    expect(operation.isRunning, isFalse);
  });

  test('cancel waits for in-flight work, skips its result, and allows retry',
      () async {
    final operation = RecoveryOperation();
    final command = Completer<int>();
    var consumed = false;
    var cleaned = false;
    final work = operation.run(() async {
      await operation.wait(command.future);
      consumed = true;
    }, onCancelled: () => cleaned = true);
    operation.cancel();
    expect(operation.isRunning, isTrue);
    await operation.run(() async => fail('overlapping operation'));
    command.complete(1);
    await work;
    expect(consumed, isFalse);
    expect(cleaned, isTrue);
    expect(operation.wasCancelled, isTrue);
    expect(operation.isRunning, isFalse);
    await operation.run(() async => consumed = true);
    expect(consumed, isTrue);
    expect(operation.wasCancelled, isFalse);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('confirmation and cancelling state at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operation = RecoveryOperation();
      final command = Completer<void>();
      final work = operation.run(() => operation.wait(command.future));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
            body: Column(children: [
          const Text('Recovering keys'),
          const LinearProgressIndicator(value: .4),
          CancelRecovery(operation: operation),
        ])),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this process?'), findsOneWidget);
      await tester.tap(find.text('Keep running'));
      await tester.pumpAndSettle();
      expect(operation.isCancelling, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(operation.isCancelling, isTrue);
      expect(find.text('Cancelling…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      command.complete();
      await work;
    });
  }
}
