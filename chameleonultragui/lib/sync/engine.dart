import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as hashing;

import 'backend.dart';
import 'crypto.dart';
import 'hlc.dart';
import 'local_source.dart';

/// Local bookkeeping for one record (`collection/id`).
class RecordMeta {
  /// Hash of the local JSON; empty for tombstones.
  String hash;

  /// HLC of the last change; the higher one wins a conflict.
  String time;

  /// Last remote version seen (compare-and-swap base); empty if never synced.
  String version;
  bool dirty;
  bool deleted;

  /// Human readable name for history views.
  String label;

  RecordMeta({
    this.hash = '',
    this.time = Hlc.zero,
    this.version = '',
    this.dirty = false,
    this.deleted = false,
    this.label = '',
  });

  factory RecordMeta.fromJson(Map<String, dynamic> json) => RecordMeta(
    hash: json['h'] as String,
    time: json['t'] as String,
    version: json['v'] as String,
    dirty: json['d'] as bool,
    deleted: json['x'] as bool,
    label: json['n'] as String,
  );

  Map<String, Object> toJson() => {
    'h': hash,
    't': time,
    'v': version,
    'd': dirty,
    'x': deleted,
    'n': label,
  };
}

/// Everything the engine persists between runs.
class SyncLedger {
  final Map<String, RecordMeta> records;
  String cursor;

  /// False until the first scan. Data that predates sync gets [Hlc.zero] so
  /// the vault's version wins when a device joins an existing vault.
  bool bootstrapped;

  SyncLedger(this.records, {this.cursor = '', this.bootstrapped = false});

  factory SyncLedger.fromJson(Map<String, dynamic> json) => SyncLedger(
    (json['records'] as Map<String, dynamic>).map(
      (key, value) =>
          MapEntry(key, RecordMeta.fromJson(value as Map<String, dynamic>)),
    ),
    cursor: json['cursor'] as String,
    bootstrapped: json['bootstrapped'] as bool,
  );

  Map<String, Object> toJson() => {
    'records': records.map((key, value) => MapEntry(key, value.toJson())),
    'cursor': cursor,
    'bootstrapped': bootstrapped,
  };
}

/// A decrypted previous version of a record.
class RecordVersion {
  final String version;
  final String time;

  /// The JSON value, or `null` for a deletion.
  final String? value;
  const RecordVersion(this.version, this.time, this.value);
}

/// Item too large to sync (gzip + encryption still above the blob limit).
const maxBlobBytes = 1 << 20;
const _maxBatchBytes = 4 << 20;
const _maxBatchRecords = 200;

/// Merges local and remote state: per-record last-writer-wins by HLC, with
/// tombstones for deletions. Stateless apart from [ledger] and [keychain].
class SyncEngine {
  final SyncSource source;
  final SyncBackend backend;
  final String vaultId;
  final Hlc hlc;
  final SyncLedger ledger;
  Keychain keychain;

  /// Records the last run could not upload because they are too large.
  final Set<String> oversized = {};

  SyncEngine({
    required this.source,
    required this.backend,
    required this.vaultId,
    required this.keychain,
    required this.hlc,
    required this.ledger,
  }) {
    for (final meta in ledger.records.values) {
      hlc.observe(meta.time);
    }
  }

  static String _hash(String json) =>
      hashing.sha1.convert(utf8.encode(json)).toString();

  static String _label(String collection, String id, String? json) {
    if (collection == 'settings' || json == null) return id;
    final value = jsonDecode(json);
    return value is Map && value['name'] is String
        ? value['name'] as String
        : id;
  }

  /// Compares the current local data with the ledger and records changes.
  Map<String, Map<String, String>> scan() {
    final snapshot = source.read();
    final initial = !ledger.bootstrapped;
    for (final MapEntry(key: collection, value: items) in snapshot.entries) {
      for (final MapEntry(key: id, value: json) in items.entries) {
        final hash = _hash(json);
        final meta = ledger.records['$collection/$id'];
        if (meta == null) {
          ledger.records['$collection/$id'] = RecordMeta(
            hash: hash,
            time: initial ? Hlc.zero : hlc.next(),
            dirty: true,
            label: _label(collection, id, json),
          );
        } else if (meta.deleted || meta.hash != hash) {
          meta
            ..hash = hash
            ..time = hlc.next()
            ..dirty = true
            ..deleted = false
            ..label = _label(collection, id, json);
        }
      }
    }
    for (final MapEntry(:key, value: meta) in ledger.records.entries) {
      final [collection, id] = _split(key);
      final items = snapshot[collection];
      if (items != null && !meta.deleted && !items.containsKey(id)) {
        meta
          ..hash = ''
          ..time = hlc.next()
          ..dirty = true
          ..deleted = true;
      }
    }
    ledger.bootstrapped = true;
    return snapshot;
  }

  static List<String> _split(String key) {
    final slash = key.indexOf('/');
    return [key.substring(0, slash), key.substring(slash + 1)];
  }

  /// One full round: pull, then push (retrying after conflicts). Returns
  /// the collections changed by remote data. Throws `epoch` when remote data
  /// needs a newer keychain.
  Future<Set<String>> sync() async {
    final changed = <String>{};
    for (var attempt = 0; ; attempt++) {
      changed.addAll(await _pull());
      try {
        await _push(scan());
        return changed;
      } on SyncException catch (error) {
        if (error.code != 'conflict' || attempt >= 3) rethrow;
      }
    }
  }

  Future<Set<String>> _pull() async {
    final changed = <String>{};
    PullResult page;
    do {
      page = await backend.pull(ledger.cursor);
      final payloads = [
        for (final record in page.records)
          (record, await _decrypt(record.key, record.blob)),
      ];
      // Rescan right before applying, with no await in between, so edits
      // made while waiting for the server are timestamped and win.
      scan();
      for (final (record, payload) in payloads) {
        if (payload == null) continue;
        final collection = _merge(record, payload);
        if (collection != null) changed.add(collection);
      }
      ledger.cursor = page.cursor;
    } while (page.more);
    return changed;
  }

  Future<Map<String, dynamic>?> _decrypt(String key, Uint8List blob) async {
    try {
      // Written after a key rotation this device has not picked up yet: stop
      // before the cursor moves past it.
      if (Keychain.blobEpoch(blob) > keychain.current) {
        throw const SyncException('epoch');
      }
      final plain = await keychain.open(vaultId, key, blob);
      final payload = jsonDecode(
        utf8.decode(GZipDecoder().decodeBytes(plain)),
      ) as Map<String, dynamic>;
      // A blob only counts for the record key it was encrypted for.
      if (await keychain.recordKey(payload['c'], payload['id']) != key) {
        return null;
      }
      return payload;
    } on SyncException {
      rethrow;
    } catch (_) {
      return null; // Undecryptable or foreign data is ignored.
    }
  }

  /// Applies a decrypted remote record if it is newer. Returns its
  /// collection if local data changed.
  String? _merge(RemoteRecord record, Map<String, dynamic> payload) {
    final collection = payload['c'] as String;
    final id = payload['id'] as String;
    final time = payload['t'] as String;
    final value = payload['v'] as String?;
    // Membership records count only under the current key, so a revoked
    // device holding old keys cannot inject devices.
    if (internalCollections.contains(collection) &&
        Keychain.blobEpoch(record.blob) < keychain.current) {
      return null;
    }
    hlc.observe(time);

    final meta = ledger.records['$collection/$id'];
    final hash = value == null ? '' : _hash(value);
    if (meta != null) {
      // Newer time wins; equal times (e.g. two bootstrapped devices) fall
      // back to the hash so every device picks the same winner.
      final order = meta.time.compareTo(time);
      if (order > 0 || (order == 0 && meta.hash.compareTo(hash) >= 0)) {
        meta.version = record.version;
        return null;
      }
    }
    source.write(collection, id, value);
    ledger.records['$collection/$id'] = RecordMeta(
      hash: hash,
      time: time,
      version: record.version,
      deleted: value == null,
      label: value == null ? meta?.label ?? id : _label(collection, id, value),
    );
    return collection;
  }

  Future<void> _push(Map<String, Map<String, String>> snapshot) async {
    final batch = <OutgoingRecord>[];
    final metas = <String, RecordMeta>{};
    var bytes = 0;
    oversized.clear();

    Future<void> flush() async {
      if (batch.isEmpty) return;
      final versions = await backend.push(batch);
      for (final MapEntry(:key, value: meta) in metas.entries) {
        meta
          ..version = versions[key] ?? meta.version
          ..dirty = false;
      }
      batch.clear();
      metas.clear();
      bytes = 0;
    }

    for (final MapEntry(key: name, value: meta) in ledger.records.entries) {
      if (!meta.dirty) continue;
      final [collection, id] = _split(name);
      final value = meta.deleted ? null : snapshot[collection]?[id];
      final key = await keychain.recordKey(collection, id);
      final plain = GZipEncoder().encodeBytes(
        utf8.encode(
          jsonEncode({'c': collection, 'id': id, 't': meta.time, 'v': value}),
        ),
      );
      final blob = await keychain.seal(vaultId, key, plain);
      if (blob.length > maxBlobBytes) {
        // Stays dirty: retried (and reported) every run until it shrinks.
        oversized.add(meta.label);
        continue;
      }
      if (batch.length >= _maxBatchRecords ||
          bytes + blob.length > _maxBatchBytes) {
        await flush();
      }
      batch.add(OutgoingRecord(key, meta.version, blob));
      metas[key] = meta;
      bytes += blob.length;
    }
    await flush();
  }

  /// Re-uploads vault bookkeeping under the current key (after rotation).
  void markInternalDirty() {
    for (final MapEntry(:key, value: meta) in ledger.records.entries) {
      if (internalCollections.contains(_split(key).first)) {
        meta
          ..dirty = true
          ..time = hlc.next();
      }
    }
  }

  /// Previous versions of a record, newest first.
  Future<List<RecordVersion>> history(String collection, String id) async {
    final key = await keychain.recordKey(collection, id);
    final versions = <RecordVersion>[];
    for (final record in await backend.history(key)) {
      final payload = await _decrypt(key, record.blob);
      if (payload != null) {
        versions.add(
          RecordVersion(
            record.version,
            payload['t'] as String,
            payload['v'] as String?,
          ),
        );
      }
    }
    return versions;
  }

  /// Makes [value] the newest local version (undo / restore). Sync to upload.
  void restore(String collection, String id, String? value) {
    source.write(collection, id, value);
    final meta = ledger.records.putIfAbsent(
      '$collection/$id',
      () => RecordMeta(),
    );
    meta
      ..hash = value == null ? '' : _hash(value)
      ..time = hlc.next()
      ..dirty = true
      ..deleted = value == null
      ..label = value == null ? meta.label : _label(collection, id, value);
  }

  /// User-visible records, most recently changed first.
  List<(String, String, RecordMeta)> recent({int limit = 100}) {
    final entries = [
      for (final MapEntry(:key, value: meta) in ledger.records.entries)
        if (!internalCollections.contains(_split(key).first))
          (_split(key).first, _split(key).last, meta),
    ]..sort((a, b) => b.$3.time.compareTo(a.$3.time));
    return entries.take(limit).toList();
  }
}
