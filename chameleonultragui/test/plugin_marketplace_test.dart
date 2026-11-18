import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/plugins/git.dart';
import 'package:chameleonultragui/plugins/marketplace.dart';
import 'package:chameleonultragui/plugins/plugin.dart';

/// Runs git in [directory] and returns trimmed stdout.
String _git(Directory directory, List<String> arguments) {
  final result = Process.runSync('git', [
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.com',
    ...arguments,
  ], workingDirectory: directory.path);
  if (result.exitCode != 0) {
    throw StateError('git $arguments: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

/// Runs git in [directory] with [input] on stdin and returns trimmed stdout.
Future<String> _gitInput(
  Directory directory,
  List<String> arguments,
  String input,
) async {
  final process = await Process.start(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  process.stdin.write(input);
  await process.stdin.close();
  final output = await process.stdout.transform(utf8.decoder).join();
  if (await process.exitCode != 0) throw StateError('git $arguments failed');
  return output.trim();
}

/// Packs everything reachable from [revision], as a server would send it.
Future<Uint8List> _pack(
  Directory directory,
  String revision, {
  bool offsets = true,
}) async {
  final process = await Process.start('git', [
    'pack-objects',
    '--stdout',
    '--revs',
    if (offsets) '--delta-base-offset',
  ], workingDirectory: directory.path);
  process.stdin.writeln(revision);
  await process.stdin.close();
  return Uint8List.fromList(
    await process.stdout.fold([], (all, chunk) => all..addAll(chunk)),
  );
}

/// Serves repositories below [root] through `git http-backend` (CGI), the
/// reference smart HTTP server every forge implements.
Future<HttpServer> _serve(Directory root) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = await request.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    final process = await Process.start(
      'git',
      ['http-backend'],
      environment: {
        'GIT_PROJECT_ROOT': root.path,
        'GIT_HTTP_EXPORT_ALL': '1',
        'REQUEST_METHOD': request.method,
        'PATH_INFO': request.uri.path,
        'QUERY_STRING': request.uri.query,
        'CONTENT_TYPE': request.headers.contentType?.toString() ?? '',
        'CONTENT_LENGTH': '${body.length}',
        'GIT_PROTOCOL': request.headers.value('Git-Protocol') ?? '',
      },
    );
    process.stdin.add(body);
    await process.stdin.close();
    final output = await process.stdout.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    var split = 0;
    while (!(output[split] == 13 && output[split + 2] == 13) &&
        !(output[split] == 10 && output[split + 1] == 10)) {
      split++;
    }
    final headers = latin1
        .decode(output.sublist(0, split))
        .split(RegExp(r'\r?\n'));
    for (final header in headers) {
      final [name, value] = header.split(': ');
      if (name == 'Status') {
        request.response.statusCode = int.parse(value.split(' ').first);
      } else {
        request.response.headers.set(name, value);
      }
    }
    request.response.add(
      output.sublist(output[split] == 13 ? split + 4 : split + 2),
    );
    await request.response.close();
  });
  return server;
}

void main() {
  late Directory root;
  late Directory work;

  setUp(() {
    root = Directory.systemTemp.createTempSync('marketplace_test');
    work = Directory('${root.path}/work')..createSync();
    // The bundled examples double as the default repository's content.
    for (final file in Directory('../docs/plugins/examples').listSync()) {
      if (file is File) {
        file.copySync('${work.path}/${file.uri.pathSegments.last}');
      }
    }
    _git(work, ['init', '-q', '-b', 'main']);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('loads and updates a repository over smart HTTP', () async {
    _git(work, ['add', '.']);
    _git(work, ['commit', '-qm', 'one']);
    _git(root, ['clone', '-q', '--bare', 'work', 'repo.git']);
    final server = await _serve(root);
    addTearDown(server.close);
    final url = 'http://127.0.0.1:${server.port}/repo.git';

    final repository = await Marketplace.load(url);
    expect(repository.name, 'ChameleonUltraGUI plugins');
    expect(repository.problems, isEmpty);
    expect(repository.listings.map((listing) => listing.id), [
      'saved-card-count',
      'toggle-theme',
      'choose-language',
      'create-dictionary',
      'offline-nested',
    ]);
    final listing = repository.listings.first;
    expect(listing.plugin.name, 'Count saved cards');
    final installed = listing.install();
    expect(installed.source, (
      repository: url,
      id: 'saved-card-count',
      version: '1.0.0',
    ));
    expect(listing.isSourceOf(installed), isTrue);
    // Independent installs (e.g. on two synced devices) share one identity.
    expect(listing.install().id, installed.id);

    // A new commit with a bumped version shows up as an update in place.
    final index = File('${work.path}/marketplace.json');
    index.writeAsStringSync(
      index.readAsStringSync().replaceFirst('"1.0.0"', '"1.1.0"'),
    );
    _git(work, ['commit', '-qam', 'two']);
    _git(work, ['push', '-q', '../repo.git', 'main']);
    final updated = (await Marketplace.load(url)).listings.first;
    expect(updated.version, '1.1.0');
    final replaced = updated.install(installed);
    expect(replaced.id, installed.id);
    expect(replaced.source?.version, '1.1.0');
  });

  test('checks out packs using offset and reference deltas', () async {
    // Similar files make git store one as a delta of the other.
    final text = List.generate(500, (line) => 'line $line').join('\n');
    File('${work.path}/a.txt').writeAsStringSync(text);
    File('${work.path}/nested/b.txt')
      ..parent.createSync()
      ..writeAsStringSync('$text\nchanged');
    _git(work, ['add', '.']);
    _git(work, ['commit', '-qm', 'one']);
    final commit = _git(work, ['rev-parse', 'HEAD']);
    for (final offsets in [true, false]) {
      final pack = await _pack(work, 'HEAD', offsets: offsets);
      final files = checkout(pack, commit);
      expect(utf8.decode(files['nested/b.txt']!), '$text\nchanged');
      expect(utf8.decode(files['a.txt']!), text);
      expect(files, contains('marketplace.json'));
    }
  });

  test('rejects packs that expand beyond the size budget', () {
    // One blob claiming 2^40 bytes; it must fail before allocating.
    final pack = Uint8List.fromList([
      ...ascii.encode('PACK'), 0, 0, 0, 2, 0, 0, 0, 1, //
      0xb0, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x02, 0x78, 0x9c,
    ]);
    expect(() => checkout(pack, '0' * 40), throwsA(isA<GitException>()));
  });

  test('rejects trees that reuse subtrees to explode the checkout', () async {
    // Each level references the level below twice: 2^20 paths from 21 trees.
    File('${work.path}/leaf').writeAsStringSync('x');
    var entry = '100644 blob ${_git(work, ['hash-object', '-w', 'leaf'])}';
    var tree = '';
    for (var level = 0; level < 20; level++) {
      tree = await _gitInput(work, ['mktree'], '$entry\ta\n$entry\tb\n');
      entry = '040000 tree $tree';
    }
    final commit = _git(work, ['commit-tree', tree, '-m', 'bomb']);
    final pack = await _pack(work, commit);
    expect(() => checkout(pack, commit), throwsA(isA<GitException>()));
  });

  test('rejects paths beyond the length bound', () async {
    File('${work.path}/leaf').writeAsStringSync('x');
    var tree = await _gitInput(work, [
      'mktree',
    ], '100644 blob ${_git(work, ['hash-object', '-w', 'leaf'])}\tleaf\n');
    // 20 levels of 60-character directory names: a path over 1024 chars.
    for (var level = 0; level < 20; level++) {
      tree = await _gitInput(work, [
        'mktree',
      ], '040000 tree $tree\t${'d' * 60}\n');
    }
    final commit = _git(work, ['commit-tree', tree, '-m', 'deep']);
    final pack = await _pack(work, commit);
    expect(() => checkout(pack, commit), throwsA(isA<GitException>()));
  });

  test('reports broken listings without hiding valid ones', () async {
    final plugin = jsonEncode(Plugin(name: 'Valid', code: '').toJson());
    final repository = await Marketplace.parse(
      'https://example.com/plugins.git',
      'commit',
      {
        'marketplace.json': utf8.encode(
          jsonEncode({
            'format': Marketplace.format,
            'version': 1,
            'plugins': [
              {'id': 'valid', 'path': 'valid.json', 'version': '1'},
              {'id': 'valid', 'path': 'valid.json', 'version': '2'},
              {'id': 'missing', 'path': 'missing.json', 'version': '1'},
              {'id': 'no-version', 'path': 'valid.json'},
            ],
          }),
        ),
        'valid.json': utf8.encode(plugin),
      },
    );
    expect(repository.name, 'plugins');
    expect(repository.listings.single.plugin.name, 'Valid');
    expect(repository.problems, hasLength(3));
    await expectLater(
      Marketplace.parse('https://example.com/x', 'commit', {}),
      throwsFormatException,
    );
  });

  test('shares envelopes between listings and bounds decoded size', () async {
    // Compresses to a few KiB but decodes to almost 8 MiB.
    final big = Plugin(name: 'Big', code: 'a' * (8 * 1024 * 1024 - 64));
    final envelope = utf8.encode(jsonEncode(big.toJson(compress: true)));
    final repository = await Marketplace.parse('https://example.com/r', 'c', {
      'marketplace.json': utf8.encode(
        jsonEncode({
          'format': Marketplace.format,
          'version': 1,
          'plugins': [
            {'id': 'same', 'path': 'big0', 'version': '1'},
            for (var i = 0; i < 9; i++)
              {'id': 'big$i', 'path': 'big$i', 'version': '1'},
          ],
        }),
      ),
      for (var i = 0; i < 9; i++) 'big$i': envelope,
    });
    final listings = repository.listings;
    expect(identical(listings[0].plugin, listings[1].plugin), isTrue);
    // Eight distinct ~8 MiB payloads fit in 64 MiB; the ninth does not.
    expect(listings, hasLength(9));
    expect(repository.problems.single, startsWith('big8:'));
  });

  test('installed source survives storage but not imports', () async {
    final plugin = Plugin(
      name: 'Installed',
      code: '',
      source: (repository: 'https://example.com/r', id: 'p', version: '1'),
    );
    final source = jsonEncode(plugin.toJson());
    expect((await Plugin.decode(source)).source, plugin.source);
    expect((await Plugin.decode(source, freshId: true)).source, isNull);
  });

  test('repository URLs must be plain https URLs', () {
    expect(
      Marketplace.normalizeUrl(' https://codeberg.org/me/plugins/ '),
      'https://codeberg.org/me/plugins',
    );
    for (final url in [
      'http://example.com/repo',
      'git@example.com:repo.git',
      'https://user:pass@example.com/repo',
      'https://example.com/repo?x=1',
      'not a url',
    ]) {
      expect(() => Marketplace.normalizeUrl(url), throwsFormatException);
    }
  });
}
