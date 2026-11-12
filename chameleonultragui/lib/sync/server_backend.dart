import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'backend.dart';
import 'crypto.dart';

/// Client for the sync server protocol (`sync/PROTOCOL.md`), shared by the
/// Cloudflare Worker and the self-hosted Rust server.
class ServerBackend implements SyncBackend {
  final Uri _base;
  final Credentials _credentials;
  final http.Client _http = http.Client();

  ServerBackend(Uri url, this._credentials)
    : _base = url.replace(
        path:
            '${url.path.replaceAll(RegExp(r'/+$'), '')}'
            '/v1/vaults/${_credentials.vaultId}',
      );

  @override
  SyncCapabilities get capabilities => const SyncCapabilities(
    realtime: true,
    history: true,
    serverEnforced: true,
  );

  Uri _uri(String path, [Map<String, String>? query]) =>
      _base.replace(path: '${_base.path}/$path', queryParameters: query);

  Future<Map<String, dynamic>?> _call(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers['Authorization'] = 'Bearer ${token ?? _credentials.token}';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await _http.send(request));
    final json = response.body.isEmpty
        ? null
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw SyncException(
        json?['error'] as String? ?? 'http',
        response.statusCode,
      );
    }
    return json;
  }

  @override
  Future<void> init(int epoch, List<NewMember> members) async {
    await _call(
      'POST',
      'init',
      body: {
        'epoch': epoch,
        'members': [for (final m in members) m.toJson()],
      },
    );
  }

  @override
  Future<KeyringEntry> keyring() async {
    final json = (await _call('GET', 'keyring'))!;
    return KeyringEntry(json['epoch'] as int, json['keychain'] as String);
  }

  @override
  Future<void> rotate(
    int fromEpoch,
    int epoch,
    Map<String, String> entries,
  ) async {
    await _call(
      'PUT',
      'keyring',
      body: {'fromEpoch': fromEpoch, 'epoch': epoch, 'entries': entries},
    );
  }

  @override
  Future<(int, List<MemberInfo>)> members() async {
    final json = (await _call('GET', 'members'))!;
    return (
      json['epoch'] as int,
      [
        for (final m in json['members'] as List)
          MemberInfo(m['id'] as String, m['kind'] as String),
      ],
    );
  }

  @override
  Future<void> addMember(NewMember member, int epoch, {String? pairing}) async {
    await _call(
      'POST',
      'members',
      body: {...member.toJson(), 'epoch': epoch, 'pairing': ?pairing},
    );
  }

  @override
  Future<void> revoke(String memberId) async {
    await _call('DELETE', 'members/$memberId');
  }

  @override
  Future<PullResult> pull(String cursor) async {
    final json = (await _call(
      'GET',
      'changes',
      query: {'since': cursor.isEmpty ? '0' : cursor},
    ))!;
    return PullResult(
      [
        for (final r in json['records'] as List)
          RemoteRecord(
            r['key'] as String,
            r['version'] as String,
            unb64(r['blob'] as String),
          ),
      ],
      json['cursor'] as String,
      json['more'] as bool,
    );
  }

  @override
  Future<Map<String, String>> push(List<OutgoingRecord> records) async {
    final json = (await _call(
      'POST',
      'records',
      body: {
        'records': [
          for (final r in records)
            {'key': r.key, 'base': r.base, 'blob': b64(r.blob)},
        ],
      },
    ))!;
    return (json['versions'] as Map).cast<String, String>();
  }

  @override
  Future<List<RemoteRecord>> history(String key) async {
    final json = (await _call('GET', 'records/$key/history'))!;
    return [
      for (final v in json['versions'] as List)
        RemoteRecord(key, v['version'] as String, unb64(v['blob'] as String)),
    ];
  }

  @override
  Future<void> openPairing(String id, String authHash) async {
    await _call('POST', 'pairings', body: {'id': id, 'authHash': authHash});
  }

  @override
  Future<void> joinPairing(String id, String authToken, String request) async {
    await _call(
      'POST',
      'pairings/$id/join',
      token: authToken,
      body: {'request': request},
    );
  }

  @override
  Future<String?> pairingRequest(String id) async =>
      (await _call('GET', 'pairings/$id'))!['request'] as String?;

  /// A fresh connection per subscription; cancelling it disconnects.
  @override
  Stream<SyncEvent> events() {
    final controller = StreamController<SyncEvent>();
    final realtime = _Realtime(
      _uri('ws', {
        'token': _credentials.token,
      }).replace(scheme: _base.scheme == 'https' ? 'wss' : 'ws'),
      controller,
    );
    return (controller
          ..onListen = realtime.connect
          ..onCancel = realtime.close)
        .stream;
  }

  @override
  void close() => _http.close();
}

/// One realtime subscription: keeps a socket open, detects dead connections
/// with an application-level ping and reconnects with capped, jittered
/// backoff. Every confirmed (re)connect emits [RecordsChanged] once so the
/// listener catches up on anything sent while it was offline.
class _Realtime {
  static const _keepalive = Duration(seconds: 45);
  static final _random = Random();

  final Uri _uri;
  final StreamController<SyncEvent> _out;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _messages;
  Timer? _timer;
  int _failures = 0;
  bool _closed = false;

  _Realtime(this._uri, this._out);

  Future<void> connect() async {
    final socket = WebSocketChannel.connect(_uri);
    _socket = socket;
    try {
      await socket.ready;
    } catch (_) {
      if (_socket == socket) _reconnect();
      return;
    }
    if (_socket != socket) return; // Closed while connecting.

    var confirmed = false;
    var answered = true;
    _messages = socket.stream.listen(
      (message) {
        answered = true;
        if (message != 'pong') {
          if (_parse(message as String) case final event?) _out.add(event);
        } else if (!confirmed) {
          // The first pong confirms the subscription (PROTOCOL.md).
          confirmed = true;
          _failures = 0;
          _out.add(const RecordsChanged());
        }
      },
      onError: (_) {}, // Followed by onDone.
      onDone: () {
        if (socket.closeCode != 4001) return _reconnect();
        close();
        _out.add(const Revoked());
      },
    );
    socket.sink.add('ping');
    _timer = Timer.periodic(_keepalive, (_) {
      // No answer to the previous ping: the connection silently died
      // (network change, sleeping NAT), so start over.
      if (!answered) return _reconnect();
      answered = false;
      socket.sink.add('ping');
    });
  }

  static SyncEvent? _parse(String message) => switch (jsonDecode(message)) {
    {'type': 'changed'} => const RecordsChanged(),
    {'type': 'keyring'} => const KeyringChanged(),
    {'type': 'members'} => const MembersChanged(),
    {'type': 'pairing', 'id': final String id} => PairingRequested(id),
    _ => null,
  };

  /// Drops the socket and tries again after a capped, jittered backoff.
  void _reconnect() {
    _drop();
    if (_closed) return;
    final seconds = min(60, 1 << min(_failures++, 6));
    final jitter = 0.5 + _random.nextDouble() / 2;
    _timer = Timer(
      Duration(milliseconds: (seconds * 1000 * jitter).round()),
      connect,
    );
  }

  void _drop() {
    _timer?.cancel();
    _messages?.cancel();
    _socket?.sink.close();
    _timer = null;
    _messages = null;
    _socket = null;
  }

  void close() {
    _closed = true;
    _drop();
  }
}
