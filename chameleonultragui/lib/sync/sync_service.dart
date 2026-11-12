import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'bip39.dart';
import 'crypto.dart';
import 'engine.dart';
import 'hlc.dart';
import 'local_source.dart';

const _stateKey = 'sync_state_v1';
const _ledgerKey = 'sync_ledger_v1';
const _pairingPrefix = 'cusync1:';
const _pairingLifetime = Duration(minutes: 10);

/// How often polling-only backends check for changes while in the foreground.
const _pollInterval = Duration(minutes: 1);

/// This device's membership in a vault. Stored in SharedPreferences next to
/// the (unencrypted) app data it protects; see `sync/README.md`.
class _Membership {
  final BackendConfig backend;
  final String vaultId;
  final String memberId;
  final String token;
  final Identity identity;
  final Keychain keychain;

  _Membership(
    this.backend,
    this.vaultId,
    this.memberId,
    this.token,
    this.identity,
    this.keychain,
  );

  _Membership withKeychain(Keychain keychain) =>
      _Membership(backend, vaultId, memberId, token, identity, keychain);

  factory _Membership.fromJson(Map<String, dynamic> json) => _Membership(
    BackendConfig.fromJson(json['backend'] as Map<String, dynamic>),
    json['vaultId'] as String,
    json['memberId'] as String,
    json['token'] as String,
    Identity(unb64(json['seed'] as String)),
    Keychain.fromJson(json['keychain'] as Map<String, dynamic>),
  );

  Map<String, Object> toJson() => {
    'backend': backend.toJson(),
    'vaultId': vaultId,
    'memberId': memberId,
    'token': token,
    'seed': b64(identity.seed),
    'keychain': keychain.toJson(),
  };
}

/// A pairing code shown by an existing device, waiting for a new one.
class PairingOffer {
  final String id;
  final PairingSecret secret;
  final String code;
  bool cancelled = false;
  PairingOffer(this.id, this.secret, this.code);
}

/// A new device asking to join, verified against the pairing secret.
class JoinRequest {
  final String deviceId;
  final String name;
  final List<int> publicKey;
  final String tokenHash;
  const JoinRequest(this.deviceId, this.name, this.publicKey, this.tokenHash);
}

class DeviceInfo {
  final String id;
  final String name;
  final DateTime? added;
  final bool isThisDevice;
  const DeviceInfo(this.id, this.name, this.added, this.isThisDevice);
}

enum SyncStatus { disabled, idle, syncing, error }

/// Owns this device's vault membership and runs the [SyncEngine] on local
/// changes (debounced) and, while the app is in the foreground, on realtime
/// events or a poll timer for backends without realtime. In the background
/// it holds no connection or timer; local changes still sync on demand.
class SyncService extends ChangeNotifier {
  final SharedPreferences _prefs;
  final PreferencesSource _source;

  /// Called after remote data changed local collections.
  void Function(Set<String> collections)? onRemoteChange;

  _Membership? _membership;
  SyncBackend? _backend;
  SyncEngine? _engine;
  StreamSubscription<SyncEvent>? _events;
  Timer? _debounce;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;
  bool _foreground = false;
  final _pairingRequests = StreamController<String>.broadcast();
  Future<void>? _running;
  bool _again = false;

  SyncStatus status = SyncStatus.disabled;
  DateTime? lastSync;
  Object? lastError;

  /// Set when another device removed this one; shown once by the UI.
  bool wasRevoked = false;

  SyncService(this._prefs) : _source = PreferencesSource(_prefs);

  bool get enabled => _membership != null;
  String? get deviceId => _membership?.memberId;
  BackendConfig? get backendConfig => _membership?.backend;
  SyncCapabilities? get capabilities => _backend?.capabilities;
  Set<String> get oversized => _engine?.oversized ?? const {};

  /// Resumes syncing with the stored membership, if any.
  void start() {
    final json = _prefs.getString(_stateKey);
    if (json == null) return;
    try {
      _activate(_Membership.fromJson(jsonDecode(json)));
    } catch (error) {
      lastError = error;
      status = SyncStatus.error;
    }
  }

  void _activate(_Membership membership) {
    _membership = membership;
    _prefs.setString(_stateKey, jsonEncode(membership.toJson()));
    final backend = membership.backend.connect(
      Credentials(membership.vaultId, membership.memberId, membership.token),
    );
    _backend = backend;
    final ledgerJson = _prefs.getString(_ledgerKey);
    _engine = SyncEngine(
      source: _source,
      backend: backend,
      vaultId: membership.vaultId,
      keychain: membership.keychain,
      hlc: Hlc(membership.memberId),
      ledger: ledgerJson == null
          ? SyncLedger({})
          : SyncLedger.fromJson(jsonDecode(ledgerJson)),
    );
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    status = SyncStatus.idle;
    notifyListeners();
    // Before the first frame the state may be unknown; assume visible.
    _onLifecycle(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  /// Visible windows (focused or not) count as foreground.
  void _onLifecycle(AppLifecycleState state) {
    final foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (foreground == _foreground) return;
    _foreground = foreground;
    foreground ? _resume() : _pause();
  }

  void _resume() {
    if (_backend!.capabilities.realtime) {
      _events = _backend!.events().listen(_onEvent);
    } else {
      _poll = Timer.periodic(_pollInterval, (_) => syncNow());
    }
    // Catch up even if the socket never connects (e.g. a proxy blocking
    // WebSockets); a successful handshake costs at most one more pull.
    syncNow();
  }

  void _pause() {
    _events?.cancel();
    _poll?.cancel();
    _events = null;
    _poll = null;
    // Upload pending edits now; a backgrounded app may never run the timer.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      syncNow();
    }
  }

  /// Stops timers, listeners and connections; keeps stored state.
  void _stop() {
    _events?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
    _lifecycle?.dispose();
    _backend?.close();
    _events = null;
    _poll = null;
    _debounce = null;
    _lifecycle = null;
    _foreground = false;
    _membership = null;
    _backend = null;
    _engine = null;
  }

  void _deactivate() {
    _stop();
    _prefs.remove(_stateKey);
    _prefs.remove(_ledgerKey);
    _source.clearInternal();
    status = SyncStatus.disabled;
    notifyListeners();
  }

  void _onEvent(SyncEvent event) {
    switch (event) {
      case RecordsChanged() || MembersChanged():
        syncNow();
      case KeyringChanged():
        _refreshKeychain().then((_) => syncNow(), onError: _fail);
      case PairingRequested(:final id):
        _pairingRequests.add(id);
      case Revoked():
        _revoked();
    }
  }

  void _revoked() {
    wasRevoked = true;
    _deactivate();
  }

  void _fail(Object error) {
    lastError = error;
    status = SyncStatus.error;
    notifyListeners();
  }

  /// Hook for local edits: syncs shortly after the last change.
  void localChanged() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  /// Runs a sync now; calls during a run schedule exactly one more run.
  Future<void> syncNow() async {
    if (!enabled) return;
    if (_running case final running?) {
      _again = true;
      return running;
    }
    final run = _runLoop();
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
  }

  Future<void> _runLoop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again && enabled);
  }

  Future<void> _syncOnce() async {
    final engine = _engine!;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      // Without server enforcement nothing rejects stale keys, so check first.
      if (!_backend!.capabilities.serverEnforced) await _refreshKeychain();
      Set<String> changed;
      try {
        changed = await engine.sync();
      } on SyncException catch (error) {
        if (error.code != 'epoch') rethrow;
        await _refreshKeychain();
        changed = await engine.sync();
      }
      _saveLedger();
      if (changed.isNotEmpty) onRemoteChange?.call(changed);
      status = SyncStatus.idle;
      lastSync = DateTime.now();
      lastError = null;
    } on SyncException catch (error) {
      _saveLedger();
      if (error.code == 'unauthorized') {
        _revoked();
        return;
      }
      status = SyncStatus.error;
      lastError = error;
    } catch (error) {
      _saveLedger();
      status = SyncStatus.error;
      lastError = error;
    }
    if (enabled) notifyListeners();
  }

  void _saveLedger() {
    if (_engine case final engine?) {
      _prefs.setString(_ledgerKey, jsonEncode(engine.ledger.toJson()));
    }
  }

  void _setKeychain(Keychain keychain) {
    final membership = _membership!.withKeychain(keychain);
    _membership = membership;
    _engine!.keychain = keychain;
    _prefs.setString(_stateKey, jsonEncode(membership.toJson()));
  }

  /// Picks up a rotated keychain. Never goes back to an older epoch, so a
  /// server cannot replay keys a revoked device knows.
  Future<void> _refreshKeychain() async {
    final membership = _membership!;
    final entry = await _backend!.keyring();
    if (entry.epoch <= membership.keychain.current) return;
    _setKeychain(
      await unwrapKeychain(
        entry.keychain,
        vaultId: membership.vaultId,
        memberId: membership.memberId,
        epoch: entry.epoch,
        identity: membership.identity,
      ),
    );
  }

  // --- vault setup ---------------------------------------------------------

  /// Creates a new vault with this device as the first member. Returns the
  /// recovery phrase, which is not stored anywhere.
  Future<String> createVault(BackendConfig config, String deviceName) async {
    final entropy = randomBytes(32);
    final recovery = await RecoveryKeys.derive(entropy);
    final device = Identity.random();
    final deviceId = b64(randomBytes(16));
    final token = b64(randomBytes(32));
    final keychain = Keychain.create();
    final backend = config.connect(
      Credentials(recovery.vaultId, deviceId, token),
    );
    try {
      await backend.init(keychain.current, [
        NewMember(
          'recovery',
          'recovery',
          hashToken(recovery.token),
          await wrapKeychain(
            keychain,
            vaultId: recovery.vaultId,
            memberId: 'recovery',
            memberPublicKey: await recovery.identity.publicKey(),
          ),
        ),
        NewMember(
          deviceId,
          'device',
          hashToken(token),
          await wrapKeychain(
            keychain,
            vaultId: recovery.vaultId,
            memberId: deviceId,
            memberPublicKey: await device.publicKey(),
          ),
        ),
      ]);
    } finally {
      backend.close();
    }
    _source.write(
      '_vault',
      'meta',
      jsonEncode({'recoveryPub': b64(await recovery.identity.publicKey())}),
    );
    await _registerSelf(deviceId, deviceName, device);
    _activate(
      _Membership(config, recovery.vaultId, deviceId, token, device, keychain),
    );
    return entropyToMnemonic(entropy);
  }

  /// Joins a vault with its recovery phrase (no other device needed).
  Future<void> joinWithPhrase(
    BackendConfig config,
    String phrase,
    String deviceName,
  ) async {
    final recovery = await RecoveryKeys.derive(mnemonicToEntropy(phrase));
    final backend = config.connect(
      Credentials(recovery.vaultId, 'recovery', recovery.token),
    );
    try {
      final entry = await backend.keyring();
      final keychain = await unwrapKeychain(
        entry.keychain,
        vaultId: recovery.vaultId,
        memberId: 'recovery',
        epoch: entry.epoch,
        identity: recovery.identity,
      );
      final device = Identity.random();
      final deviceId = b64(randomBytes(16));
      final token = b64(randomBytes(32));
      await backend.addMember(
        NewMember(
          deviceId,
          'device',
          hashToken(token),
          await wrapKeychain(
            keychain,
            vaultId: recovery.vaultId,
            memberId: deviceId,
            memberPublicKey: await device.publicKey(),
          ),
        ),
        keychain.current,
      );
      await _registerSelf(deviceId, deviceName, device);
      _activate(
        _Membership(
          config,
          recovery.vaultId,
          deviceId,
          token,
          device,
          keychain,
        ),
      );
    } finally {
      backend.close();
    }
  }

  Future<void> _registerSelf(
    String deviceId,
    String name,
    Identity identity,
  ) async {
    _prefs.remove(_ledgerKey);
    wasRevoked = false;
    _source.write(
      '_devices',
      deviceId,
      jsonEncode({
        'name': name,
        'pub': b64(await identity.publicKey()),
        'added': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  // --- pairing --------------------------------------------------------------

  /// Opens a pairing mailbox and returns the code to show as QR / text.
  Future<PairingOffer> startPairing() async {
    final membership = _membership!;
    final secret = PairingSecret.random();
    final id = b64(randomBytes(16));
    await _backend!.openPairing(id, hashToken(await secret.authToken()));
    final code =
        _pairingPrefix +
        b64(
          utf8.encode(
            jsonEncode({
              'b': membership.backend.toJson(),
              'v': membership.vaultId,
              'p': id,
              's': b64(secret.secret),
            }),
          ),
        );
    return PairingOffer(id, secret, code);
  }

  /// Waits for a new device to answer [offer]. Throws `expired`/`mac`.
  Future<JoinRequest> waitForJoin(PairingOffer offer) async {
    final deadline = DateTime.now().add(_pairingLifetime);
    while (!offer.cancelled && DateTime.now().isBefore(deadline)) {
      final raw = await _backend!.pairingRequest(offer.id);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final fields = [
          json['id'] as String,
          json['name'] as String,
          json['pub'] as String,
          json['tokenHash'] as String,
        ];
        // The MAC proves the request came from someone holding the code,
        // not from the server substituting its own key.
        if (await offer.secret.mac(fields) != json['mac']) {
          throw const SyncException('mac');
        }
        return JoinRequest(fields[0], fields[1], unb64(fields[2]), fields[3]);
      }
      // Realtime backends announce the request; polling is the fallback.
      await _pairingRequests.stream
          .firstWhere((id) => id == offer.id)
          .timeout(
            Duration(seconds: _backend!.capabilities.realtime ? 10 : 2),
            onTimeout: () => offer.id,
          );
    }
    throw const SyncException('expired');
  }

  /// Admits a verified [request]: hands it the keychain and lists it.
  Future<void> approve(PairingOffer offer, JoinRequest request) async {
    final membership = _membership!;
    await _backend!.addMember(
      NewMember(
        request.deviceId,
        'device',
        request.tokenHash,
        await wrapKeychain(
          membership.keychain,
          vaultId: membership.vaultId,
          memberId: request.deviceId,
          memberPublicKey: request.publicKey,
        ),
      ),
      membership.keychain.current,
      pairing: offer.id,
    );
    _source.write(
      '_devices',
      request.deviceId,
      jsonEncode({
        'name': request.name,
        'pub': b64(request.publicKey),
        'added': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    await syncNow();
  }

  /// Joins with a pairing code from another device. [onWaiting] receives this
  /// device's fingerprint to compare with the approving device.
  Future<void> joinWithCode(
    String code,
    String deviceName, {
    void Function(String fingerprint)? onWaiting,
    bool Function()? cancelled,
  }) async {
    final trimmed = code.trim();
    if (!trimmed.startsWith(_pairingPrefix)) {
      throw const FormatException('Not a pairing code');
    }
    final json = jsonDecode(
      utf8.decode(unb64(trimmed.substring(_pairingPrefix.length))),
    ) as Map<String, dynamic>;
    final config = BackendConfig.fromJson(json['b'] as Map<String, dynamic>);
    final vaultId = json['v'] as String;
    final secret = PairingSecret(unb64(json['s'] as String));
    final device = Identity.random();
    final deviceId = b64(randomBytes(16));
    final token = b64(randomBytes(32));
    final publicKey = await device.publicKey();
    final fields = [deviceId, deviceName, b64(publicKey), hashToken(token)];

    final backend = config.connect(Credentials(vaultId, deviceId, token));
    try {
      await backend.joinPairing(
        json['p'] as String,
        await secret.authToken(),
        jsonEncode({
          'id': fields[0],
          'name': fields[1],
          'pub': fields[2],
          'tokenHash': fields[3],
          'mac': await secret.mac(fields),
        }),
      );
      onWaiting?.call(fingerprint(publicKey));

      final deadline = DateTime.now().add(_pairingLifetime);
      while (true) {
        if (cancelled?.call() ?? false) throw const SyncException('cancelled');
        if (DateTime.now().isAfter(deadline)) {
          throw const SyncException('expired');
        }
        try {
          final entry = await backend.keyring();
          final keychain = await unwrapKeychain(
            entry.keychain,
            vaultId: vaultId,
            memberId: deviceId,
            epoch: entry.epoch,
            identity: device,
          );
          _prefs.remove(_ledgerKey);
          wasRevoked = false;
          _activate(
            _Membership(config, vaultId, deviceId, token, device, keychain),
          );
          return;
        } on SyncException catch (error) {
          if (error.code != 'unauthorized') rethrow;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    } finally {
      backend.close();
    }
  }

  // --- devices ---------------------------------------------------------------

  List<DeviceInfo> devices() {
    final records = _source.read()['_devices'] ?? {};
    return [
      for (final MapEntry(key: id, value: json) in records.entries)
        if (jsonDecode(json) case {'name': String name} && final data)
          DeviceInfo(
            id,
            name,
            DateTime.tryParse(data['added'] as String? ?? ''),
            id == deviceId,
          ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Removes another device and rotates the vault keys so it cannot read
  /// anything written from now on.
  Future<void> revoke(String memberId) async {
    await syncNow();
    await _backend!.revoke(memberId);
    _source.write('_devices', memberId, null);
    await _rotateKeys();
    await syncNow();
  }

  Future<void> _rotateKeys() async {
    await _refreshKeychain();
    final membership = _membership!;
    final next = membership.keychain.rotated();
    final (_, members) = await _backend!.members();
    final records = _source.read();
    final entries = <String, String>{};
    for (final member in members) {
      // Keys only go to members this device can verify via encrypted records.
      final pub = switch (member.kind) {
        'recovery' => _field(records['_vault']?['meta'], 'recoveryPub'),
        _ => _field(records['_devices']?[member.id], 'pub'),
      };
      if (pub == null) throw const SyncException('members');
      entries[member.id] = await wrapKeychain(
        next,
        vaultId: membership.vaultId,
        memberId: member.id,
        memberPublicKey: unb64(pub),
      );
    }
    await _backend!.rotate(membership.keychain.current, next.current, entries);
    _setKeychain(next);
    _engine!.markInternalDirty();
  }

  static String? _field(String? json, String field) =>
      json == null ? null : (jsonDecode(json) as Map)[field] as String?;

  /// Leaves the vault. Local data stays; nothing syncs anymore.
  Future<void> leave() async {
    try {
      _source.write('_devices', deviceId!, null);
      await syncNow();
      await _backend!.revoke(deviceId!);
    } catch (_) {
      // Leaving must work offline too; the entry can be revoked later.
    }
    _deactivate();
  }

  // --- history ----------------------------------------------------------------

  List<(String, String, RecordMeta)> recent() => _engine?.recent() ?? const [];

  Future<List<RecordVersion>> history(String collection, String id) =>
      _engine!.history(collection, id);

  /// Restores an older version (or re-deletes) and syncs it.
  Future<void> restore(String collection, String id, String? value) async {
    _engine!.restore(collection, id, value);
    _saveLedger();
    onRemoteChange?.call({collection});
    await syncNow();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
