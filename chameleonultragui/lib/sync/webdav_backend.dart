import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend.dart';
import 'crypto.dart';

/// Stores a vault in a WebDAV folder:
///
/// ```
/// <url>/<vaultId>/keyring.json      {"epoch": n, "members": {id: {"kind", "keychain"}}}
/// <url>/<vaultId>/records/<key>     encrypted blobs, ETags are versions
/// <url>/<vaultId>/pairings/<id>.json
/// ```
///
/// Change detection is one `PROPFIND Depth: 1` listing ETags. There is no
/// history, no realtime and no server-side enforcement: every device shares
/// the WebDAV login, so revocation relies on key rotation alone.
class WebDavBackend implements SyncBackend {
  final Uri _base;
  final Credentials _credentials;
  final String _auth;
  final http.Client _http = http.Client();

  WebDavBackend(WebDavConfig config, this._credentials)
    : _base = config.url.replace(
        path:
            '${config.url.path.replaceAll(RegExp(r'/+$'), '')}'
            '/${_credentials.vaultId}/',
      ),
      _auth =
          'Basic ${base64.encode(utf8.encode('${config.user}:${config.password}'))}';

  @override
  SyncCapabilities get capabilities => const SyncCapabilities(
    realtime: false,
    history: false,
    serverEnforced: false,
  );

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, _base.resolve(path))
      ..headers.addAll({'Authorization': _auth, ...headers});
    if (body is String) request.body = body;
    if (body is List<int>) request.bodyBytes = body;
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SyncException('unauthorized', response.statusCode);
    }
    return response;
  }

  void _expect(http.Response response, String code) {
    if (response.statusCode >= 400) {
      throw SyncException(code, response.statusCode);
    }
  }

  // --- keyring.json -------------------------------------------------------

  Future<(Map<String, dynamic>, String)> _readKeyring() async {
    final response = await _send('GET', 'keyring.json');
    if (response.statusCode == 404) throw const SyncException('not_found', 404);
    _expect(response, 'http');
    return (
      jsonDecode(response.body) as Map<String, dynamic>,
      response.headers['etag'] ?? '',
    );
  }

  /// Read-modify-write of keyring.json guarded by its ETag.
  Future<void> _updateKeyring(
    void Function(Map<String, dynamic> keyring) update,
  ) async {
    final (keyring, etag) = await _readKeyring();
    update(keyring);
    final response = await _send(
      'PUT',
      'keyring.json',
      body: jsonEncode(keyring),
      headers: {'If-Match': etag, 'Content-Type': 'application/json'},
    );
    if (response.statusCode == 412) throw const SyncException('conflict', 409);
    _expect(response, 'http');
  }

  Map<String, dynamic> _members(Map<String, dynamic> keyring) =>
      keyring['members'] as Map<String, dynamic>;

  @override
  Future<void> init(int epoch, List<NewMember> members) async {
    // The configured folder must exist; MKCOL on existing folders is 405, fine.
    for (final path in ['', 'records/', 'pairings/']) {
      await _send('MKCOL', path);
    }
    final response = await _send(
      'PUT',
      'keyring.json',
      body: jsonEncode({
        'epoch': epoch,
        'members': {
          for (final m in members)
            m.id: {'kind': m.kind, 'keychain': m.keychain},
        },
      }),
      headers: {'If-None-Match': '*', 'Content-Type': 'application/json'},
    );
    if (response.statusCode == 412) throw const SyncException('exists', 409);
    _expect(response, 'http');
  }

  @override
  Future<KeyringEntry> keyring() async {
    final (keyring, _) = await _readKeyring();
    final entry = _members(keyring)[_credentials.memberId];
    if (entry == null) throw const SyncException('unauthorized', 401);
    return KeyringEntry(keyring['epoch'] as int, entry['keychain'] as String);
  }

  @override
  Future<void> rotate(int fromEpoch, int epoch, Map<String, String> entries) =>
      _updateKeyring((keyring) {
        final members = _members(keyring);
        if (keyring['epoch'] != fromEpoch || epoch <= fromEpoch) {
          throw const SyncException('epoch', 409);
        }
        if (members.length != entries.length ||
            !members.keys.every(entries.containsKey)) {
          throw const SyncException('members', 409);
        }
        entries.forEach((id, keychain) => members[id]['keychain'] = keychain);
        keyring['epoch'] = epoch;
      });

  @override
  Future<(int, List<MemberInfo>)> members() async {
    final (keyring, _) = await _readKeyring();
    return (
      keyring['epoch'] as int,
      [
        for (final MapEntry(:key, :value) in _members(keyring).entries)
          MemberInfo(key, value['kind'] as String),
      ],
    );
  }

  @override
  Future<void> addMember(NewMember member, int epoch, {String? pairing}) async {
    await _updateKeyring((keyring) {
      if (keyring['epoch'] != epoch) throw const SyncException('epoch', 409);
      if (_members(keyring).containsKey(member.id)) {
        throw const SyncException('exists', 409);
      }
      _members(keyring)[member.id] = {
        'kind': member.kind,
        'keychain': member.keychain,
      };
    });
    if (pairing != null) await _send('DELETE', 'pairings/$pairing.json');
  }

  @override
  Future<void> revoke(String memberId) async {
    if (memberId == 'recovery') throw const SyncException('forbidden', 403);
    await _updateKeyring((keyring) {
      if (_members(keyring).remove(memberId) == null) {
        throw const SyncException('not_found', 404);
      }
    });
  }

  // --- records ------------------------------------------------------------

  /// Lists `records/` as key -> ETag.
  Future<Map<String, String>> _list() async {
    final response = await _send(
      'PROPFIND',
      'records/',
      body:
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
          '<d:getetag/></d:prop></d:propfind>',
      headers: {'Depth': '1', 'Content-Type': 'application/xml'},
    );
    _expect(response, 'http');
    final result = <String, String>{};
    final responses = RegExp(
      r'<(?:\w+:)?response\b.*?</(?:\w+:)?response>',
      dotAll: true,
    );
    final href = RegExp(r'<(?:\w+:)?href>(.*?)</', dotAll: true);
    final etag = RegExp(r'<(?:\w+:)?getetag>(.*?)</', dotAll: true);
    for (final match in responses.allMatches(response.body)) {
      final block = match[0]!;
      final path = href.firstMatch(block)?[1];
      final tag = etag.firstMatch(block)?[1];
      if (path == null || tag == null) continue;
      final name = Uri.decodeComponent(
        path
            .split('/')
            .lastWhere((segment) => segment.isNotEmpty, orElse: () => ''),
      );
      if (name.isNotEmpty && name != 'records') {
        result[name] = tag.replaceAll('&quot;', '"').trim();
      }
    }
    return result;
  }

  /// The cursor is the ETag listing of the previous pull.
  @override
  Future<PullResult> pull(String cursor) async {
    final previous = cursor.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(cursor) as Map<String, dynamic>;
    final current = await _list();
    final changed = [
      for (final MapEntry(:key, :value) in current.entries)
        if (previous[key] != value) key,
    ];
    final records = <RemoteRecord>[];
    // Small parallel batches keep latency low without hammering the server.
    for (var i = 0; i < changed.length; i += 8) {
      records.addAll(
        await Future.wait(
          changed.skip(i).take(8).map((key) async {
            final response = await _send('GET', 'records/$key');
            _expect(response, 'http');
            return RemoteRecord(
              key,
              response.headers['etag'] ?? current[key]!,
              response.bodyBytes,
            );
          }),
        ),
      );
    }
    return PullResult(records, jsonEncode(current), false);
  }

  /// Not atomic across records: each PUT is its own compare-and-swap.
  @override
  Future<Map<String, String>> push(List<OutgoingRecord> records) async {
    final versions = <String, String>{};
    for (final record in records) {
      final response = await _send(
        'PUT',
        'records/${record.key}',
        body: record.blob,
        headers: {
          if (record.base.isEmpty) 'If-None-Match': '*',
          if (record.base.isNotEmpty) 'If-Match': record.base,
          'Content-Type': 'application/octet-stream',
        },
      );
      if (response.statusCode == 412) {
        throw const SyncException('conflict', 409);
      }
      _expect(response, 'http');
      // Some servers omit the ETag on PUT.
      final etag =
          response.headers['etag'] ??
          (await _send('HEAD', 'records/${record.key}')).headers['etag'];
      versions[record.key] = etag ?? '';
    }
    return versions;
  }

  @override
  Future<List<RemoteRecord>> history(String key) async => const [];

  // --- pairing ------------------------------------------------------------

  @override
  Future<void> openPairing(String id, String authHash) async {
    final response = await _send(
      'PUT',
      'pairings/$id.json',
      body: jsonEncode({
        'authHash': authHash,
        'expires': DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        'request': null,
      }),
      headers: {'If-None-Match': '*', 'Content-Type': 'application/json'},
    );
    if (response.statusCode == 412) throw const SyncException('exists', 409);
    _expect(response, 'http');
  }

  Future<(Map<String, dynamic>, String)> _pairing(String id) async {
    final response = await _send('GET', 'pairings/$id.json');
    if (response.statusCode == 404) throw const SyncException('not_found', 404);
    _expect(response, 'http');
    final pairing = jsonDecode(response.body) as Map<String, dynamic>;
    if ((pairing['expires'] as int) < DateTime.now().millisecondsSinceEpoch) {
      throw const SyncException('not_found', 404);
    }
    return (pairing, response.headers['etag'] ?? '');
  }

  @override
  Future<void> joinPairing(String id, String authToken, String request) async {
    final (pairing, etag) = await _pairing(id);
    if (pairing['authHash'] != hashToken(authToken)) {
      throw const SyncException('unauthorized', 401);
    }
    if (pairing['request'] != null) throw const SyncException('exists', 409);
    pairing['request'] = request;
    final response = await _send(
      'PUT',
      'pairings/$id.json',
      body: jsonEncode(pairing),
      headers: {'If-Match': etag, 'Content-Type': 'application/json'},
    );
    if (response.statusCode == 412) throw const SyncException('exists', 409);
    _expect(response, 'http');
  }

  @override
  Future<String?> pairingRequest(String id) async =>
      (await _pairing(id)).$1['request'] as String?;

  @override
  Stream<SyncEvent> events() => const Stream.empty();

  @override
  void close() => _http.close();
}
