const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, cpSync, writeFileSync, mkdirSync, readFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const { gunzipSync } = require('node:zlib');

test('bundles a copied project with Git ignores, exact resource keys and compression', t => {
  const root = mkdtempSync(join(tmpdir(), 'gui-plugin-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  cpSync(join(__dirname, 'development'), root, { recursive: true });
  cpSync(join(__dirname, 'build-plugin.js'), join(root, 'build-plugin.js'));
  execFileSync('git', ['init', '-q', root]);
  mkdirSync(join(root, 'assets'));
  writeFileSync(join(root, 'assets/.gitignore'), '*.txt\n!keep.txt\n.gitignore\n');
  writeFileSync(join(root, 'assets/keep.txt'), 'héllo');
  writeFileSync(join(root, 'assets/ignored.txt'), 'secret');
  execFileSync('git', ['add', '-f', 'assets/ignored.txt'], { cwd: root });
  writeFileSync(join(root, 'assets/image.bin'), Buffer.from([0xff, 0x00, 0x80]));
  writeFileSync(join(root, 'helpers.lua'), 'return { label = "Hello" }');
  function build() {
    execFileSync(process.execPath, ['--require', join(root, 'dist/guard.cjs'), join(root, 'build-plugin.js'), root]);
    return JSON.parse(readFileSync(join(root, 'dist/plugin.plugin.json'), 'utf8'));
  }
  mkdirSync(join(root, 'dist'), { recursive: true });
  // Simulate an unreadable ignored directory even when tests run as root.
  writeFileSync(join(root, 'dist/guard.cjs'), `
    const fs = require('node:fs');
    const original = fs.readdirSync;
    fs.readdirSync = function (path, ...args) {
      if (require('node:path').basename(path) === 'dist') throw new Error('ignored directory read');
      return original.call(this, path, ...args);
    };
  `);
  const plain = build();
  assert.equal(plain.format, 'chameleon-ultra-gui-plugin');
  assert.equal(plain.version, 1);
  assert.equal(plain.data.code, readFileSync(join(root, 'main.lua'), 'utf8'));
  assert.deepEqual(plain.data.resources, {
    'assets/image.bin': '/wCA', 'assets/keep.txt': 'héllo', 'helpers.lua': 'return { label = "Hello" }',
  });
  assert.deepEqual(build().data, plain.data, 'rebuild must not include its own output');
  writeFileSync(join(root, 'plugin.config.json'), JSON.stringify({ name: 'Compressed', compress: true }));
  const compressed = build();
  assert.equal(compressed.encoding, 'gzip+base64');
  assert.deepEqual(JSON.parse(gunzipSync(Buffer.from(compressed.data, 'base64'))), plain.data);
  // Metadata can take the full envelope to its limit while the payload stays small.
  const limit = 16 * 1024 * 1024;
  const description = 'x'.repeat(limit - Buffer.byteLength(JSON.stringify({ ...plain, description: '' })));
  writeFileSync(join(root, 'plugin.config.json'), JSON.stringify({ name: plain.name, id: plain.id, description }));
  build();
  assert.equal(readFileSync(join(root, 'dist/plugin.plugin.json')).length, limit);
  writeFileSync(join(root, 'plugin.config.json'), JSON.stringify({ name: 'Oversized' }));
  writeFileSync(join(root, 'main.lua'), 'x'.repeat(8 * 1024 * 1024));
  const oversized = spawnSync(process.execPath, [join(root, 'build-plugin.js'), root], { encoding: 'utf8' });
  assert.equal(oversized.status, 1);
  assert.match(oversized.stderr, /exceed 8 MiB/);
});

test('Lua declarations cover every explicit host adapter', () => {
  const { readdirSync } = require('node:fs');
  const api = join(__dirname, '../../chameleonultragui/lib/plugins');
  const declarations = readFileSync(join(__dirname, 'development/types/chameleon.d.lua'), 'utf8');
  for (const file of readdirSync(api).filter(name => /api\.dart$/.test(name))) {
    const source = readFileSync(join(api, file), 'utf8');
    for (const [, method] of source.matchAll(/'((?:ui|classic|device|slots|ultralight|settings|recovery|cards|dictionaries)\.\w+)':/g)) {
      assert.ok(declarations.includes(`function chameleon.${method}(`), method);
    }
  }
});
