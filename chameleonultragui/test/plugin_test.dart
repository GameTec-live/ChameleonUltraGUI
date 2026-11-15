import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chameleonultragui/plugins/plugin.dart';
import 'package:chameleonultragui/plugins/runtime.dart';

void main() {
  test(
    'plain and compressed exports preserve metadata, code and resources',
    () async {
      final plugin = Plugin(
        name: 'Test',
        description: 'A description',
        color: 0xffabcdef,
        code: 'return 42',
        resources: {'module.lua': 'return { value = 42 }', 'text': 'héllo'},
      );
      for (final compress in [false, true]) {
        final source = jsonEncode(plugin.toJson(compress: compress));
        final decoded = await Plugin.decode(source);
        expect(decoded.toJson(), plugin.toJson());
        expect(
          (await Plugin.decode(source, freshId: true)).id,
          isNot(plugin.id),
        );
      }
    },
  );

  test(
    'compressed imports must fit the uncompressed persisted envelope',
    () async {
      final description = String.fromCharCodes(
        Uint8List(12 * 1024 * 1024)..fillRange(0, 12 * 1024 * 1024, 100),
      );
      final code = String.fromCharCodes(
        Uint8List(6 * 1024 * 1024)..fillRange(0, 6 * 1024 * 1024, 97),
      );
      final envelope = Plugin(
        name: 'Large metadata',
        code: '',
      ).toJson(compress: true);
      envelope['description'] = description;
      envelope['data'] = base64Encode(
        gzip.encode(utf8.encode(jsonEncode({'code': code, 'resources': {}}))),
      );
      await expectLater(
        Plugin.decode(jsonEncode(envelope)),
        throwsFormatException,
      );
      expect(
        () => Plugin(
          name: 'Large metadata',
          description: description,
          code: code,
        ),
        throwsFormatException,
      );
      final accepted = Plugin(
        name: 'Fits',
        description: description,
        code: 'return 42',
      );
      expect(
        (await Plugin.decode(jsonEncode(accepted.toJson()))).description,
        description,
      );
    },
  );

  test('unknown format and invalid resource values are rejected', () async {
    await expectLater(
      Plugin.decode('{"format":"other","version":1}'),
      throwsFormatException,
    );
    final data = Plugin(name: 'Test', code: '').toJson();
    data['data'] = {
      'code': '',
      'resources': {'bad': 1},
    };
    await expectLater(
      Plugin.decode(jsonEncode(data)),
      throwsA(isA<TypeError>()),
    );
  });

  test(
    'Lua calls namespaced async APIs, reads local modules and uses codecs',
    () async {
      final calls = <List<Object?>>[];
      final runtime = PluginRuntime();
      await runtime.run(
        Plugin(
          name: 'Test',
          resources: {'module': 'return {answer = 42}'},
          code: '''
      assert(io == nil and os == nil and package == nil and loadfile == nil)
      local module = require('module')
      assert(module.answer == 42)
      assert(chameleon.resources.get('module') == 'return {answer = 42}')
      assert(chameleon.codec.base64Decode(chameleon.codec.base64Encode('hello')) == 'hello')
      assert(chameleon.codec.decompress(chameleon.codec.compress('hello')) == 'hello')
      local result = chameleon.device.test({1, 2, 255}, {name = 'héllo 世界'})
      assert(result.answer == 42)
      assert(result.bytes[1] == 5)
    ''',
        ),
        ['device.test'],
        (method, args) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          calls.add([method, ...args]);
          return {
            'answer': 42,
            'bytes': [5, 6],
          };
        },
      );
      expect(calls, [
        [
          'device.test',
          [1, 2, 255],
          {'name': 'héllo 世界'},
        ],
      ]);
    },
  );

  test('Lua errors propagate', () async {
    await expectLater(
      PluginRuntime().run(
        Plugin(name: 'Test', code: 'error("broken")'),
        [],
        (_, _) async => null,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('broken'),
        ),
      ),
    );
  });

  test('stop terminates a runaway Lua loop', () async {
    final runtime = PluginRuntime();
    final running = runtime.run(
      Plugin(name: 'Loop', code: 'while true do end'),
      [],
      (_, _) async => null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    runtime.stop();
    await running.timeout(const Duration(seconds: 5));
  });
  test(
    'stop waits for an in-flight host operation before releasing the run',
    () async {
      final runtime = PluginRuntime();
      final entered = Completer<void>();
      final release = Completer<void>();
      var finished = false;
      final running = runtime
          .run(
            Plugin(name: 'Wait', code: 'chameleon.device.wait()'),
            ['device.wait'],
            (_, _) async {
              entered.complete();
              await release.future;
              return null;
            },
          )
          .then((_) => finished = true);
      await entered.future;
      runtime.stop();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(finished, false);
      release.complete();
      await running;
      expect(finished, true);
    },
  );

  test(
    'host errors can be handled by Lua and resources do not cross runs',
    () async {
      final runtime = PluginRuntime();
      await runtime.run(
        Plugin(
          name: 'Errors',
          code: '''
      local ok, err = pcall(chameleon.device.fail)
      assert(not ok)
      local found = pcall(chameleon.resources.get, 'other-plugin-resource')
      assert(not found)
      local decoded = pcall(chameleon.codec.base64Decode, '!invalid!')
      assert(not decoded)
      local binary = chameleon.codec.base64DecodeBytes('AAH/')
      assert(binary[1] == 0 and binary[2] == 1 and binary[3] == 255)
      assert(chameleon.codec.base64EncodeBytes(binary) == 'AAH/')
      local restored = chameleon.codec.decompressBytes(chameleon.codec.compressBytes(binary))
      assert(restored[1] == 0 and restored[3] == 255)
    ''',
        ),
        ['device.fail'],
        (_, _) async => throw StateError('expected'),
      );
    },
  );

  test('compressed imports reject oversized expanded data', () async {
    final envelope = Plugin(name: 'Large', code: '').toJson(compress: true);
    envelope['data'] = base64Encode(
      gzip.encode(List.filled(Plugin.maxDataBytes + 1, 65)),
    );
    await expectLater(
      Plugin.decode(jsonEncode(envelope)),
      throwsFormatException,
    );
  });
}
