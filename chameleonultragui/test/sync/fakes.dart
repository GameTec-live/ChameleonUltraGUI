import 'dart:typed_data';

import 'package:chameleonultragui/sync/backend.dart';
import 'package:chameleonultragui/sync/local_source.dart';

/// In-memory [SyncSource]: collection -> id -> JSON.
class MemorySource implements SyncSource {
  final Map<String, Map<String, String>> data = {
    'cards': {},
    'settings': {},
    '_devices': {},
  };

  @override
  Map<String, Map<String, String>> read() => {
    for (final e in data.entries) e.key: Map.of(e.value),
  };

  @override
  void write(String collection, String id, String? json) {
    final items = data.putIfAbsent(collection, () => {});
    json == null ? items.remove(id) : items[id] = json;
  }
}

/// In-memory backend with the server's compare-and-swap and history rules.
class MemoryBackend implements SyncBackend {
  final records = <String, (int, Uint8List)>{};
  final previous = <String, List<(int, Uint8List)>>{};
  var seq = 0;

  /// Run while a pull or push is "in flight", e.g. to simulate a
  /// concurrent edit.
  void Function()? onPull;
  void Function()? onPush;

  @override
  SyncCapabilities get capabilities => const SyncCapabilities(
    realtime: false,
    history: true,
    serverEnforced: true,
  );

  @override
  Future<PullResult> pull(String cursor) async {
    onPull?.call();
    final since = int.tryParse(cursor) ?? 0;
    final changed = records.entries.where((e) => e.value.$1 > since).toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    return PullResult(
      [
        for (final e in changed)
          RemoteRecord(e.key, '${e.value.$1}', e.value.$2),
      ],
      '$seq',
      false,
    );
  }

  @override
  Future<Map<String, String>> push(List<OutgoingRecord> batch) async {
    onPush?.call();
    final stale = batch.where(
      (r) => (records[r.key] == null ? '' : '${records[r.key]!.$1}') != r.base,
    );
    if (stale.isNotEmpty) throw const SyncException('conflict', 409);
    final versions = <String, String>{};
    for (final r in batch) {
      if (records[r.key] case final old?) {
        previous.putIfAbsent(r.key, () => []).insert(0, old);
      }
      records[r.key] = (++seq, r.blob);
      versions[r.key] = '$seq';
    }
    return versions;
  }

  @override
  Future<List<RemoteRecord>> history(String key) async => [
    for (final (version, blob) in [?records[key], ...?previous[key]])
      RemoteRecord(key, '$version', blob),
  ];

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
