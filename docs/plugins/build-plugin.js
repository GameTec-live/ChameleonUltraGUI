#!/usr/bin/env node
// Run with Node.js 22+: node build-plugin.js [plugin-folder]
const { readFileSync, lstatSync, writeFileSync, mkdirSync } = require('node:fs');
const { resolve, dirname, join } = require('node:path');
const { spawnSync } = require('node:child_process');
const { randomUUID } = require('node:crypto');
const { gzipSync } = require('node:zlib');

try {
  const root = resolve(process.argv[2] || '.');
  const configPath = join(root, 'plugin.config.json');
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const { name, description = '', color = 0xffff5722, compress = false } = config;
  if (typeof name !== 'string' || !name.trim() || name.length > 200) {
    throw new Error('name must be a nonempty string of at most 200 characters');
  }
  if (typeof description !== 'string' || !Number.isInteger(color) || color < 0 || color > 0xffffffff || typeof compress !== 'boolean') {
    throw new Error('Invalid description, color or compress in plugin.config.json');
  }
  const output = resolve(root, config.output || 'dist/plugin.plugin.json');
  const script = resolve(__filename);
  // Let Git prune ignored trees before reading their contents.
  const listed = spawnSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', '.'], {
    cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  });
  if (listed.error || listed.status !== 0) {
    throw new Error('Git file lookup failed; install Git and run git init in the plugin folder. ' + (listed.error?.message || listed.stderr));
  }
  const files = [...new Set(listed.stdout.split('\0').filter(Boolean))];
  // --no-index also respects ignores for files that happen to be tracked.
  const ignored = spawnSync('git', ['check-ignore', '--no-index', '-z', '--stdin'], {
    cwd: root, input: files.map(file => file + '\0').join(''), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  });
  if (ignored.error || ![0, 1].includes(ignored.status)) {
    throw new Error('Git ignore lookup failed; install Git and run git init in the plugin folder. ' + (ignored.error?.message || ignored.stderr));
  }
  const excluded = new Set(ignored.stdout.split('\0'));
  const resources = Object.create(null);
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
  for (const file of files.sort()) {
    if (excluded.has(file)) continue;
    const path = join(root, file);
    if ([script, configPath, output, join(root, 'main.lua')].includes(path)) continue;
    // Skip deleted tracked files, symlinks and submodule directories.
    if (!lstatSync(path, { throwIfNoEntry: false })?.isFile()) continue;
    const bytes = readFileSync(path);
    try { resources[file] = decoder.decode(bytes); }
    catch { resources[file] = bytes.toString('base64'); }
  }
  const payload = { code: readFileSync(join(root, 'main.lua'), 'utf8'), resources };
  const data = JSON.stringify(payload);
  if (Buffer.byteLength(data) > 8 * 1024 * 1024) throw new Error('Plugin code and resources exceed 8 MiB');
  const envelope = {
    format: 'chameleon-ultra-gui-plugin', version: 1, id: config.id || randomUUID(),
    name, description, color, encoding: 'json', data: payload,
  };
  if (typeof envelope.id !== 'string') throw new Error('id must be a string');
  if (Buffer.byteLength(JSON.stringify(envelope)) > 16 * 1024 * 1024) throw new Error('Plugin envelope exceeds 16 MiB');
  if (compress) {
    envelope.encoding = 'gzip+base64';
    envelope.data = gzipSync(data).toString('base64');
  }
  const result = JSON.stringify(envelope);
  if (Buffer.byteLength(result) > 16 * 1024 * 1024) throw new Error('Plugin file exceeds 16 MiB');
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, result);
  console.log(`Built ${output} (${Object.keys(resources).length} resources)`);
} catch (error) {
  console.error(`Plugin build failed: ${error.message}`);
  process.exitCode = 1;
}
