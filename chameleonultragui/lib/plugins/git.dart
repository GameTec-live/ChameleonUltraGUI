import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class GitException implements Exception {
  final String message;
  GitException(this.message);
  @override
  String toString() => message;
}

/// Minimal read-only client for Git's smart HTTP transport (protocol v2).
///
/// It speaks only the standard Git wire protocol, so it works with every forge
/// and with a plain `git http-backend`. It resolves HEAD and downloads a
/// shallow snapshot of that commit's files; there is no history or checkout.
class GitRemote {
  /// Upper bound for any single response, including the snapshot pack.
  static const maxResponseBytes = 64 * 1024 * 1024;

  /// Upper bound for all unpacked objects together, so a small hostile pack
  /// cannot expand into an out-of-memory crash.
  static const maxExpandedBytes = 256 * 1024 * 1024;

  /// Bounds each request including its body, so a stalled server fails.
  static const requestTimeout = Duration(minutes: 2);

  final http.Client _client;
  String _url;
  Future<Set<String>>? _fetchFeatures;

  GitRemote(String url, this._client)
    : _url = url.replaceFirst(RegExp(r'/+$'), '');

  /// The commit HEAD points to.
  Future<String> head() async {
    await _features();
    final response = await _command('ls-refs', ['ref-prefix HEAD']);
    for (final line in _lines(response)) {
      final [oid, ref, ...] = line.split(' ');
      if (ref == 'HEAD') return oid;
    }
    throw GitException('Repository has no HEAD (is it empty?)');
  }

  /// Files of [commit]'s tree keyed by slash-separated path. Symlinks and
  /// submodules are skipped.
  Future<Map<String, Uint8List>> files(String commit) async {
    final shallow = (await _features()).contains('shallow');
    final response = await _command('fetch', [
      'want $commit',
      if (shallow) 'deepen 1',
      'ofs-delta',
      'no-progress',
      'done',
    ]);
    final pack = BytesBuilder(copy: false);
    var inPack = false;
    for (final packet in _packets(response)) {
      if (packet == null) continue;
      if (!inPack) {
        final line = utf8.decode(packet).trimRight();
        if (line.startsWith('ERR ')) throw GitException(line.substring(4));
        inPack = line == 'packfile';
        continue;
      }
      switch (packet.first) {
        case 1:
          pack.add(Uint8List.sublistView(packet, 1));
        case 3:
          throw GitException(utf8.decode(packet.sublist(1)).trim());
      }
    }
    if (!inPack) throw GitException('Server sent no packfile');
    final bytes = pack.takeBytes();
    // Inflating and hashing a pack is CPU bound; keep it off the UI isolate.
    return Isolate.run(() => checkout(bytes, commit));
  }

  /// Reads the capability advertisement once. Also follows redirects, so
  /// later POSTs go to the final repository URL like Git itself does.
  Future<Set<String>> _features() => _fetchFeatures ??= () async {
    final request = http.Request(
      'GET',
      Uri.parse('$_url/info/refs?service=git-upload-pack'),
    )..headers['Git-Protocol'] = 'version=2';
    final (response, body) = await _send(request);
    if (response case http.BaseResponseWithUrl(:final url)) {
      _url = url
          .toString()
          .split('?')
          .first
          .replaceFirst(RegExp(r'/info/refs$'), '');
    }
    final lines = _lines(body).toList();
    if (lines.firstOrNull?.startsWith('# service=') ?? false) {
      lines.removeAt(0);
    }
    if (lines.firstOrNull != 'version 2') {
      throw GitException('Server does not support Git protocol v2');
    }
    final fetch = lines.firstWhere(
      (line) => line.startsWith('fetch'),
      orElse: () => throw GitException('Server does not support fetch'),
    );
    return fetch.replaceFirst(RegExp(r'^fetch=?'), '').split(' ').toSet();
  }();

  Future<Uint8List> _command(String command, List<String> arguments) async {
    final body = BytesBuilder(copy: false)
      ..add(_pkt('command=$command\n'))
      ..add(utf8.encode('0001'));
    for (final argument in arguments) {
      body.add(_pkt('$argument\n'));
    }
    body.add(utf8.encode('0000'));
    final request = http.Request('POST', Uri.parse('$_url/git-upload-pack'))
      ..headers.addAll({
        'Git-Protocol': 'version=2',
        'Content-Type': 'application/x-git-upload-pack-request',
        'Accept': 'application/x-git-upload-pack-result',
      })
      ..bodyBytes = body.takeBytes();
    return (await _send(request)).$2;
  }

  Future<(http.StreamedResponse, Uint8List)> _send(http.BaseRequest request) =>
      _receive(request).timeout(
        requestTimeout,
        onTimeout: () => throw GitException('Repository timed out'),
      );

  Future<(http.StreamedResponse, Uint8List)> _receive(
    http.BaseRequest request,
  ) async {
    final response = await _client.send(request);
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      body.add(chunk);
      if (body.length > maxResponseBytes) {
        throw GitException('Repository is too large');
      }
    }
    if (response.statusCode != 200) {
      throw GitException(
        'HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}'.trim(),
      );
    }
    return (response, body.takeBytes());
  }
}

Uint8List _pkt(String line) {
  final bytes = utf8.encode(line);
  return Uint8List.fromList([
    ...ascii.encode((bytes.length + 4).toRadixString(16).padLeft(4, '0')),
    ...bytes,
  ]);
}

/// Splits pkt-line framing. Special packets (flush, delimiter, response end)
/// are yielded as null.
Iterable<Uint8List?> _packets(Uint8List data) sync* {
  var position = 0;
  while (position < data.length) {
    if (position + 4 > data.length) throw GitException('Truncated response');
    final length = int.tryParse(
      ascii.decode(data.sublist(position, position + 4), allowInvalid: true),
      radix: 16,
    );
    if (length == null || (length > 2 && length < 4)) {
      throw GitException('Invalid Git response');
    }
    if (length < 4) {
      position += 4;
      yield null;
      continue;
    }
    if (position + length > data.length) {
      throw GitException('Truncated response');
    }
    yield Uint8List.sublistView(data, position + 4, position + length);
    position += length;
  }
}

Iterable<String> _lines(Uint8List data) =>
    _packets(data).nonNulls.map((packet) => utf8.decode(packet).trimRight());

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

const _commit = 1, _tree = 2, _blob = 3, _ofsDelta = 6, _refDelta = 7;
const _typeNames = {1: 'commit', 2: 'tree', 3: 'blob', 4: 'tag'};

/// Upper bounds for tree entries visited by [checkout] and for each path.
/// The path bound also limits tree depth.
const maxCheckoutEntries = 100000, maxPathLength = 1024;

/// Unpacks [pack] and returns the files of [commit]'s tree. Exposed for tests.
Map<String, Uint8List> checkout(Uint8List pack, String commit) {
  final objects = _unpack(pack);
  (int, Uint8List) object(String id, int type) => switch (objects[id]) {
    final found? when found.$1 == type => found,
    _ => throw GitException('Pack is missing ${_typeNames[type]} $id'),
  };
  final header = latin1.decode(object(commit, _commit).$2);
  final tree = RegExp(r'^tree ([0-9a-f]{40})').firstMatch(header)?.group(1);
  if (tree == null) throw GitException('Invalid commit $commit');

  final files = <String, Uint8List>{};
  // Trees can reference one subtree under many names; bound the expansion.
  var entries = 0;
  void walk(String id, String prefix) {
    final data = object(id, _tree).$2;
    var position = 0;
    while (position < data.length) {
      if (++entries > maxCheckoutEntries) {
        throw GitException('Repository is too large');
      }
      final space = data.indexOf(0x20, position);
      final nul = data.indexOf(0, space);
      if (space < 0 || nul < 0 || nul + 21 > data.length) {
        throw GitException('Invalid tree $id');
      }
      final mode = ascii.decode(data.sublist(position, space));
      final String name;
      final entry = _hex(data.sublist(nul + 1, nul + 21));
      position = nul + 21;
      try {
        name = utf8.decode(data.sublist(space + 1, nul));
      } on FormatException {
        // Git allows non-UTF-8 names; the JSON index can never reference them.
        continue;
      }
      final path = '$prefix$name';
      if (path.length > maxPathLength) throw GitException('Path is too long');
      if (mode == '40000') {
        walk(entry, '$path/');
      } else if (mode.startsWith('100')) {
        files[path] = object(entry, _blob).$2;
      }
    }
  }

  walk(tree, '');
  return files;
}

typedef _Entry = ({int type, Uint8List data, Object? base});

/// Inflates every pack object and resolves deltas, keyed by object id.
Map<String, (int, Uint8List)> _unpack(Uint8List pack) {
  final view = ByteData.sublistView(pack);
  if (pack.length < 12 || ascii.decode(pack.sublist(0, 4)) != 'PACK') {
    throw GitException('Invalid pack');
  }
  final count = view.getUint32(8);
  var budget = GitRemote.maxExpandedBytes;
  // Checked before allocating, using the sizes the pack declares.
  void reserve(int bytes) {
    budget -= bytes;
    if (budget < 0) throw GitException('Repository is too large');
  }

  final entries = <int, _Entry>{};
  var position = 12;
  for (var i = 0; i < count; i++) {
    final start = position;
    var byte = pack[position++];
    final type = (byte >> 4) & 7;
    var size = byte & 15;
    for (var shift = 4; byte & 0x80 != 0; shift += 7) {
      byte = pack[position++];
      size |= (byte & 0x7f) << shift;
    }
    Object? base;
    if (type == _ofsDelta) {
      byte = pack[position++];
      var offset = byte & 0x7f;
      while (byte & 0x80 != 0) {
        byte = pack[position++];
        offset = ((offset + 1) << 7) | (byte & 0x7f);
      }
      base = start - offset;
    } else if (type == _refDelta) {
      base = _hex(pack.sublist(position, position + 20));
      position += 20;
    }
    // Skip the two byte zlib header; Inflate stops exactly after the final
    // deflate block, then the four byte Adler-32 trailer follows.
    final input = InputMemoryStream(pack, offset: position + 2);
    reserve(size);
    final data = Inflate.stream(input, output: _BoundedOutput(size)).getBytes();
    if (data.length != size) throw GitException('Corrupt pack object');
    entries[start] = (type: type, data: data, base: base);
    position += 2 + input.position + 4;
  }

  final objects = <String, (int, Uint8List)>{};
  final resolved = <int, (int, Uint8List)>{};
  final offsets = <String, int>{};
  // Returns null while a REF_DELTA base has not been resolved yet.
  (int, Uint8List)? resolve(int offset) {
    if (resolved[offset] case final done?) return done;
    final entry = entries[offset];
    if (entry == null) throw GitException('Invalid delta base');
    final baseOffset = switch (entry.base) {
      final int offset => offset,
      final String id => offsets[id],
      _ => null,
    };
    final (int, Uint8List) result;
    if (entry.base == null) {
      result = (entry.type, entry.data);
    } else if (baseOffset == null) {
      return null;
    } else if (resolve(baseOffset) case (final type, final data)) {
      result = (type, _applyDelta(data, entry.data, reserve));
    } else {
      return null;
    }
    final (type, data) = result;
    final id = _hex(
      sha1
          .convert(
            (BytesBuilder(copy: false)
                  ..add(latin1.encode('${_typeNames[type]} ${data.length}\x00'))
                  ..add(data))
                .takeBytes(),
          )
          .bytes,
    );
    offsets[id] = offset;
    objects[id] = result;
    return resolved[offset] = result;
  }

  var pending = entries.keys.toList();
  while (pending.isNotEmpty) {
    final next = pending.where((offset) => resolve(offset) == null).toList();
    if (next.length == pending.length) {
      throw GitException('Pack references missing objects');
    }
    pending = next;
  }
  return objects;
}

Uint8List _applyDelta(
  Uint8List base,
  Uint8List delta,
  void Function(int bytes) reserve,
) {
  var position = 0;
  int size() {
    var value = 0;
    for (var shift = 0; ; shift += 7) {
      final byte = delta[position++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return value;
    }
  }

  if (size() != base.length) throw GitException('Delta base size mismatch');
  final length = size();
  reserve(length);
  final output = Uint8List(length);
  var written = 0;
  while (position < delta.length) {
    final op = delta[position++];
    if (op & 0x80 != 0) {
      var offset = 0, length = 0;
      for (var i = 0; i < 4; i++) {
        if (op & (1 << i) != 0) offset |= delta[position++] << (8 * i);
      }
      for (var i = 0; i < 3; i++) {
        if (op & (0x10 << i) != 0) length |= delta[position++] << (8 * i);
      }
      if (length == 0) length = 0x10000;
      output.setRange(written, written + length, base, offset);
      written += length;
    } else if (op != 0) {
      output.setRange(written, written + op, delta, position);
      position += op;
      written += op;
    } else {
      throw GitException('Invalid delta');
    }
  }
  if (written != output.length) throw GitException('Delta size mismatch');
  return output;
}

/// Inflate output that refuses to grow past the object size the pack declared.
class _BoundedOutput extends OutputMemoryStream {
  final int limit;
  _BoundedOutput(this.limit) : super(size: limit);

  void _grow(int bytes) {
    if (length + bytes > limit) throw GitException('Corrupt pack object');
  }

  @override
  void writeByte(int value) {
    _grow(1);
    super.writeByte(value);
  }

  @override
  void writeBackReference(int distance, int count) {
    _grow(count);
    super.writeBackReference(distance, count);
  }

  @override
  void writeStream(InputStream stream) {
    _grow(stream.length);
    super.writeStream(stream);
  }
}
