import 'dart:typed_data';

import 'server_backend.dart';
import 'webdav_backend.dart';

/// Where a vault is stored. Serialized into the local sync state and into
/// pairing codes (so a WebDAV pairing code carries the WebDAV credentials).
sealed class BackendConfig {
  const BackendConfig();

  Map<String, String> toJson();

  SyncBackend connect(Credentials credentials);

  static BackendConfig fromJson(Map<String, dynamic> json) => switch (json) {
    {'t': 'server', 'u': String url} => ServerConfig(Uri.parse(url)),
    {'t': 'webdav', 'u': String url, 'n': String user, 'w': String pass} =>
      WebDavConfig(Uri.parse(url), user, pass),
    _ => throw const FormatException('Unknown sync backend'),
  };
}

/// The sync server protocol (Cloudflare Worker or the Rust server).
class ServerConfig extends BackendConfig {
  final Uri url;
  const ServerConfig(this.url);

  @override
  Map<String, String> toJson() => {'t': 'server', 'u': url.toString()};

  @override
  SyncBackend connect(Credentials credentials) =>
      ServerBackend(url, credentials);
}

/// Any WebDAV folder (Nextcloud, ownCloud, rclone, ...).
class WebDavConfig extends BackendConfig {
  final Uri url;
  final String user;
  final String password;
  const WebDavConfig(this.url, this.user, this.password);

  @override
  Map<String, String> toJson() => {
    't': 'webdav',
    'u': url.toString(),
    'n': user,
    'w': password,
  };

  @override
  SyncBackend connect(Credentials credentials) =>
      WebDavBackend(this, credentials);
}

/// Who is talking to the backend: a vault member and its bearer token.
class Credentials {
  final String vaultId;
  final String memberId;
  final String token;
  const Credentials(this.vaultId, this.memberId, this.token);
}

class SyncCapabilities {
  /// Pushes change notifications; otherwise the client polls.
  final bool realtime;

  /// Keeps previous versions of every record.
  final bool history;

  /// Enforces membership and the current key epoch server side. Without it a
  /// revoked device keeps storage access (only key rotation protects data).
  final bool serverEnforced;

  const SyncCapabilities({
    required this.realtime,
    required this.history,
    required this.serverEnforced,
  });
}

class RemoteRecord {
  final String key;
  final String version;
  final Uint8List blob;
  const RemoteRecord(this.key, this.version, this.blob);
}

class PullResult {
  final List<RemoteRecord> records;
  final String cursor;
  final bool more;
  const PullResult(this.records, this.cursor, this.more);
}

class OutgoingRecord {
  final String key;

  /// Version this write is based on; empty for a record never seen remotely.
  final String base;
  final Uint8List blob;
  const OutgoingRecord(this.key, this.base, this.blob);
}

class MemberInfo {
  final String id;
  final String kind;
  const MemberInfo(this.id, this.kind);
}

class NewMember {
  final String id;
  final String kind;
  final String tokenHash;
  final String keychain;
  const NewMember(this.id, this.kind, this.tokenHash, this.keychain);

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind,
    'tokenHash': tokenHash,
    'keychain': keychain,
  };
}

class KeyringEntry {
  final int epoch;
  final String keychain;
  const KeyringEntry(this.epoch, this.keychain);
}

sealed class SyncEvent {
  const SyncEvent();
}

class RecordsChanged extends SyncEvent {
  const RecordsChanged();
}

class KeyringChanged extends SyncEvent {
  const KeyringChanged();
}

class MembersChanged extends SyncEvent {
  const MembersChanged();
}

class PairingRequested extends SyncEvent {
  final String id;
  const PairingRequested(this.id);
}

/// This device was removed from the vault.
class Revoked extends SyncEvent {
  const Revoked();
}

/// A protocol error; [code] is the `error` field of the response
/// (`conflict`, `epoch`, `unauthorized`, `members`, `quota`, ...).
class SyncException implements Exception {
  final String code;
  final int? status;
  const SyncException(this.code, [this.status]);

  @override
  String toString() =>
      'SyncException($code${status == null ? '' : ', $status'})';
}

/// Storage for one vault. Implementations only move opaque blobs; all
/// encryption and merging happens in the engine.
abstract interface class SyncBackend {
  SyncCapabilities get capabilities;

  Future<void> init(int epoch, List<NewMember> members);

  /// The caller's own wrapped keychain.
  Future<KeyringEntry> keyring();

  /// Replaces every member's keychain atomically. [entries] must cover
  /// exactly the current members.
  Future<void> rotate(int fromEpoch, int epoch, Map<String, String> entries);

  Future<(int, List<MemberInfo>)> members();

  Future<void> addMember(NewMember member, int epoch, {String? pairing});

  Future<void> revoke(String memberId);

  /// Records written after [cursor] (`''` = from the start).
  Future<PullResult> pull(String cursor);

  /// Atomic compare-and-swap write where supported; returns new versions.
  Future<Map<String, String>> push(List<OutgoingRecord> records);

  /// Current version first, then previous ones (empty without history).
  Future<List<RemoteRecord>> history(String key);

  Future<void> openPairing(String id, String authHash);

  Future<void> joinPairing(String id, String authToken, String request);

  Future<String?> pairingRequest(String id);

  /// Realtime notifications. Connects on listen and disconnects when the
  /// subscription is cancelled; an empty stream for polling-only backends.
  Stream<SyncEvent> events();

  void close();
}
