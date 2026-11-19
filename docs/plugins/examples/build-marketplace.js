#!/usr/bin/env node
// Run with Node.js 22+: node build-marketplace.js [repository-folder]
//
// Regenerates marketplace.json from every plugins/<id>.plugin.json file and
// the optional marketplace.config.json. A listing's version defaults to a hash
// of the plugin's content, so any change to it is offered as an update, while
// reformatting or line-ending conversion is not.
const { readFileSync, readdirSync, writeFileSync, existsSync } = require('node:fs');
const { join } = require('node:path');
const { createHash } = require('node:crypto');

try {
  const root = process.argv[2] || '.';
  const configPath = join(root, 'marketplace.config.json');
  const config = existsSync(configPath) ? JSON.parse(readFileSync(configPath, 'utf8')) : {};
  const { name, author, plugins: overrides = {} } = config;
  const optionalString = value => value === undefined || typeof value === 'string';
  if (!optionalString(name) || !optionalString(author) || typeof overrides !== 'object' || Array.isArray(overrides)) {
    throw new Error('marketplace.config.json: name and author must be strings, plugins an object');
  }

  const suffix = '.plugin.json';
  const files = readdirSync(join(root, 'plugins'), { withFileTypes: true })
    .filter(entry => entry.isFile() && entry.name.endsWith(suffix))
    .map(entry => entry.name)
    .sort();
  const plugins = files.map(file => {
    const id = file.slice(0, -suffix.length);
    const path = `plugins/${file}`;
    const bytes = readFileSync(join(root, path));
    let envelope;
    try { envelope = JSON.parse(bytes.toString('utf8')); } catch (error) { throw new Error(`${path}: ${error.message}`); }
    if (envelope?.format !== 'chameleon-ultra-gui-plugin' || envelope.version !== 1) {
      throw new Error(`${path} is not a plugin file; export plugins from the GUI or build them with build-plugin.js`);
    }
    const override = overrides[id] ?? {};
    if (!optionalString(override.version) || !optionalString(override.author)) {
      throw new Error(`marketplace.config.json: plugins.${id} version and author must be strings`);
    }
    const version = override.version ?? createHash('sha256').update(JSON.stringify(envelope)).digest('hex').slice(0, 8);
    const listingAuthor = override.author ?? author;
    return { id, path, version, ...(listingAuthor && { author: listingAuthor }) };
  });
  for (const id of Object.keys(overrides)) {
    if (!plugins.some(plugin => plugin.id === id)) console.warn(`Warning: plugins.${id} in marketplace.config.json has no plugins/${id}${suffix}`);
  }

  const manifest = { format: 'chameleon-ultra-gui-marketplace', version: 1, ...(name && { name }), plugins };
  writeFileSync(join(root, 'marketplace.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(`Listed ${plugins.length} plugins in marketplace.json`);
} catch (error) {
  console.error(`Marketplace build failed: ${error.message}`);
  process.exitCode = 1;
}
