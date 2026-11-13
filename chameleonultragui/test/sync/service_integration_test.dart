// End-to-end test of SyncService against a running backend:
//   SYNC_URL=http://127.0.0.1:8787 flutter test test/sync/service_integration_test.dart
//   WEBDAV_URL=http://user:pass@127.0.0.1:8080/dav flutter test test/sync/...
// Skipped when neither is set.
import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/sync/backend.dart';
import 'package:chameleonultragui/sync/crypto.dart';
import 'package:chameleonultragui/sync/sync_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

BackendConfig? _config() {
  final env = Platform.environment;
  if (env['SYNC_URL'] case final server?) {
    return ServerConfig(Uri.parse(server));
  }
  if (env['WEBDAV_URL'] case final webdav?) {
    final uri = Uri.parse(webdav);
    final [user, password] = uri.userInfo.split(':');
    return WebDavConfig(uri.replace(userInfo: ''), user, password);
  }
  return null;
}

/// A device with its own SharedPreferences: each mock store is separate and
/// every instance reads from its own cache.
Future<(SyncService, SharedPreferences)> device() async {
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return (SyncService(prefs), prefs);
}

/// Waits for [check]; polling-only backends get explicit syncs meanwhile.
Future<void> eventually(
  bool Function() check, [
  List<SyncService> poll = const [],
]) async {
  for (var i = 0; i < 100 && !check(); i++) {
    for (final service in poll) {
      await service.syncNow();
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  expect(check(), isTrue);
}

/// Moves the app between foreground and background through valid steps.
void setLifecycle(AppLifecycleState target) {
  const order = [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
  ];
  final binding = TestWidgetsFlutterBinding.instance;
  var index = order.indexOf(
    binding.lifecycleState ?? AppLifecycleState.resumed,
  );
  final step = order.indexOf(target) > index ? 1 : -1;
  while (order[index] != target) {
    index += step;
    binding.handleAppLifecycleStateChanged(order[index]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test blocks real HTTP by default.
  HttpOverrides.global = null;

  final config = _config();

  test(
    'create, pair, realtime, history, revoke and recover',
    () async {
      final config = _config()!;
      final (a, prefsA) = await device();
      final card = jsonEncode({'id': 'card-1', 'name': 'Office'});
      await prefsA.setStringList('cards', [card]);
      await prefsA.setInt('app_theme', 4);
      final phrase = await a.createVault(config, 'Laptop');
      expect(phrase.split(' '), hasLength(24));
      await a.syncNow();

      // Pair a second device through the mailbox.
      final (b, prefsB) = await device();
      await prefsB.setInt('app_theme', 1);
      final offer = await a.startPairing();
      String? shownOnB;
      final joining = b.joinWithCode(
        offer.code,
        'Phone',
        onWaiting: (fingerprint) => shownOnB = fingerprint,
      );
      final request = await a.waitForJoin(offer);
      expect(request.name, 'Phone');
      await a.approve(offer, request);
      await joining;
      expect(fingerprint(request.publicKey), shownOnB);
      await b.syncNow();
      expect(prefsB.getStringList('cards'), [card]);
      // The vault's data beats the joining device's older local settings.
      expect(prefsB.getInt('app_theme'), 4);
      expect(a.devices().map((d) => d.name), ['Laptop', 'Phone']);
      final capabilities = a.capabilities!;
      // Without realtime, devices only learn about changes when they sync.
      final pollA = capabilities.realtime ? <SyncService>[] : [a];
      final pollB = capabilities.realtime ? <SyncService>[] : [b];

      // A setting changed on B reaches A (pushed by realtime backends).
      await prefsB.setInt('app_theme', 2);
      await b.syncNow();
      await eventually(() => prefsA.getInt('app_theme') == 2, pollA);

      // In the background nothing is connected; resuming catches up.
      setLifecycle(AppLifecycleState.hidden);
      // wsgidav's ETags only change with the mtime second or the size.
      await Future.delayed(const Duration(milliseconds: 1100));
      await prefsB.setInt('app_theme', 30);
      await b.syncNow();
      await Future.delayed(const Duration(milliseconds: 500));
      expect(prefsA.getInt('app_theme'), 2);
      setLifecycle(AppLifecycleState.resumed);
      await eventually(() => prefsA.getInt('app_theme') == 30);

      // Deletions propagate; with history they can be undone from any device.
      await prefsB.setStringList('cards', []);
      await b.syncNow();
      await eventually(() => prefsA.getStringList('cards')!.isEmpty, pollA);
      if (capabilities.history) {
        final versions = await a.history('cards', 'card-1');
        expect(versions.first.value, isNull);
        await a.restore('cards', 'card-1', versions[1].value);
      } else {
        await a.restore('cards', 'card-1', card);
      }
      await eventually(() => prefsB.getStringList('cards')!.length == 1, pollB);

      // Revoke B: it is cut off and the vault moves to a new key epoch.
      // An earlier attempt removed B on the server but failed before
      // rotating keys; repeating the removal still rotates.
      final credentialsA = Credentials(
        _vaultId(prefsA),
        a.deviceId!,
        _token(prefsA),
      );
      final deviceB = b.deviceId!;
      await config.connect(credentialsA).revoke(deviceB);
      await a.revoke(deviceB);
      await eventually(() => !b.enabled, pollB);
      expect(b.wasRevoked, isTrue);
      expect(a.devices().map((d) => d.name), ['Laptop']);
      final (epoch, members) = await config.connect(credentialsA).members();
      expect(epoch, 2);
      expect(members.map((m) => m.id), isNot(contains(deviceB)));

      // Recover on a third device with only the phrase.
      final (c, prefsC) = await device();
      await c.joinWithPhrase(config, phrase, 'Tablet');
      await c.syncNow();
      expect(prefsC.getStringList('cards'), [card]);
      expect(prefsC.getInt('app_theme'), 30);
      await eventually(() => a.devices().length == 2, pollA);

      for (final service in [a, b, c]) {
        service.dispose();
      }
    },
    skip: config == null ? 'set SYNC_URL or WEBDAV_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

String _vaultId(SharedPreferences prefs) =>
    jsonDecode(prefs.getString('sync_state_v1')!)['vaultId'] as String;

String _token(SharedPreferences prefs) =>
    jsonDecode(prefs.getString('sync_state_v1')!)['token'] as String;
