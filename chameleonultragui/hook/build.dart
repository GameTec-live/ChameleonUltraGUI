import 'dart:io';
import 'package:hooks/hooks.dart';

String? _findWasmPack() {
  final name = Platform.isWindows ? 'wasm-pack.exe' : 'wasm-pack';
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  final candidates = [
    '$home/.cargo/bin/$name',
    ...?Platform.environment['PATH']
        ?.split(Platform.isWindows ? ';' : ':')
        .map((d) => '$d/$name'),
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

void main(List<String> args) {
  build(args, (input, output) async {
    final packageRoot = input.packageRoot.toFilePath();
    final rustDir = '${packageRoot}rust';
    final webPkgDir = '${packageRoot}web/pkg';
    final jsFile = '$webPkgDir/recovery_wasm.js';

    if (!Directory(rustDir).existsSync()) return;

    final exe = _findWasmPack();
    if (exe == null) {
      throw Exception(
        'wasm-pack not found in PATH or ~/.cargo/bin.\n'
        'Install it: cargo install wasm-pack\n'
        'Or: curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh',
      );
    }

    print('[recovery-wasm] Building WASM with wasm-pack ($exe)...');
    final result = await Process.run(
      exe,
      [
        'build',
        '--release',
        '--target',
        'no-modules',
        '--no-opt',
        '--out-dir',
        webPkgDir,
      ],
      workingDirectory: rustDir,
      environment: Platform.environment,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw Exception('wasm-pack failed with exit code ${result.exitCode}');
    }

    print('[recovery-wasm] Patching JS glue for shared-memory WASM...');
    final file = File(jsFile);
    if (file.existsSync()) {
      var code = file.readAsStringSync();

      // let -> var so wasm_bindgen lands on globalThis/window
      code = code.replaceFirst('let wasm_bindgen', 'var wasm_bindgen');

      // patch __wbg_init to handle {module_or_path, memory} from FRB workers
      final pattern = RegExp(
        r'async function __wbg_init\((\w+),\s*(\w+)\)\s*\{',
      );
      final match = pattern.firstMatch(code);
      if (match != null && !code.contains('initSync(input.module_or_path')) {
        final original = match.group(0)!;
        final arg1 = match.group(1)!;
        final patched =
            '$original\n    if (typeof $arg1 === \'object\' && $arg1 !== null && $arg1.module_or_path) {\n        return initSync($arg1.module_or_path, $arg1.memory);\n    }';
        code = code.replaceFirst(original, patched);
      }

      file.writeAsStringSync(code);
      print('[recovery-wasm] JS glue patched.');
    }

    print('[recovery-wasm] WASM build complete.');
  });
}
