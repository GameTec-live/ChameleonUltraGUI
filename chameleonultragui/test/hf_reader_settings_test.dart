import 'dart:async';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/hf_reader_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ReaderSettingsFake {
  bool supported = true;
  (int, int, int, int) config = (1, 2, 0, 1);
  final writes = <(int, int, int, int)>[];
  bool failRead = false;
  bool failWrite = false;
  int reads = 0;
  Completer<void>? pendingWrite;

  Future<(int, int, int, int)?> load() async {
    if (!supported) return null;
    reads++;
    if (failRead) throw StateError('read failed');
    return config;
  }

  Future<void> hf14aSetConfig(int bcc, int cl2, int cl3, int rats) async {
    writes.add((bcc, cl2, cl3, rats));
    if (pendingWrite != null) await pendingWrite!.future;
    if (failWrite) throw StateError('write failed');
    config = (bcc, cl2, cl3, rats);
  }
}

Widget readerApp(ReaderSettingsFake communicator, VoidCallback onChanged) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: HfReaderSettings(
            onLoad: communicator.load,
            onSave: communicator.hf14aSetConfig,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

List<int?> values(WidgetTester tester) => tester
    .widgetList<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    )
    .map((field) => field.initialValue)
    .toList();

void main() {
  testWidgets('loads current overrides, edits and sends all four in order', (
    tester,
  ) async {
    final communicator = ReaderSettingsFake();
    var changes = 0;
    await tester.pumpWidget(readerApp(communicator, () => changes++));
    await tester.pumpAndSettle();
    expect(values(tester), [1, 2, 0, 1]);
    expect(communicator.writes, isEmpty);

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use card BCC even if invalid').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(communicator.writes, [(2, 2, 0, 1)]);
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset writes standard config and prevents concurrent writes', (
    tester,
  ) async {
    final communicator = ReaderSettingsFake();
    communicator.pendingWrite = Completer<void>();
    await tester.pumpWidget(readerApp(communicator, () {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to default'));
    await tester.pump();
    expect(communicator.writes, [(0, 0, 0, 0)]);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(values(tester), [1, 2, 0, 1]);
    communicator.pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(values(tester), [0, 0, 0, 0]);
  });

  testWidgets('hides controls when reader configuration is unsupported', (
    tester,
  ) async {
    final settings = ReaderSettingsFake()..supported = false;
    await tester.pumpWidget(readerApp(settings, () {}));
    await tester.pumpAndSettle();
    expect(find.text('HF reader configuration'), findsNothing);
    expect(settings.reads, 0);
  });

  testWidgets('read failure can be retried', (tester) async {
    final communicator = ReaderSettingsFake()..failRead = true;
    await tester.pumpWidget(readerApp(communicator, () {}));
    await tester.pumpAndSettle();
    expect(find.textContaining('read failed'), findsOneWidget);
    communicator.failRead = false;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(values(tester), [1, 2, 0, 1]);
  });

  testWidgets('failed reset keeps values and allows retry without success', (
    tester,
  ) async {
    final communicator = ReaderSettingsFake()..failWrite = true;
    var changes = 0;
    await tester.pumpWidget(readerApp(communicator, () => changes++));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(find.textContaining('write failed'), findsOneWidget);
    expect(values(tester), [1, 2, 0, 1]);
    expect(changes, 0);
    communicator.failWrite = false;
    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(values(tester), [0, 0, 0, 0]);
    expect(changes, 1);
  });
}
