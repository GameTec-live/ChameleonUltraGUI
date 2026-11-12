# Sync

End-to-end encrypted sync of settings, saved cards, dictionaries and plugins
between Chameleon Ultra GUI installs. No accounts: a vault is identified by its
recovery phrase, devices by their own keys.

| folder | what |
| --- | --- |
| [`PROTOCOL.md`](PROTOCOL.md) | wire protocol + crypto formats (the contract) |
| `worker/` | Cloudflare Worker + SQLite Durable Objects, runs on the free plan |
| `server/` | self-hostable Rust server, single SQLite file |
| `conformance/` | protocol test suite, runs against either server |
| `../chameleonultragui/lib/sync/` | client: engine, crypto, backends |

The app also syncs to any **WebDAV** folder (Nextcloud, ownCloud, rclone, …)
without a sync server; see [Backends](#backends) for what that gives up.

## How it works

- **Data model.** Every card, folder, dictionary, plugin and synced setting is
  one record. Conflicts resolve per record, last writer wins by hybrid logical
  clock. Deletions are tombstones.
- **Keys.** A random *vault key* encrypts records (XChaCha20-Poly1305). It is
  wrapped (X25519) once per member: every device has its own key pair, and
  the 24-word recovery phrase derives one more "recovery" key pair. The
  phrase is shown once and never stored.
- **Pairing.** An existing device shows a QR / text code; the new device
  scans it, both show the same fingerprint, the existing device approves.
- **Revocation.** Removing a device deletes its server token immediately and
  rotates the vault key, so it cannot read anything written afterwards. Data
  it already synced stays on it; nothing can undo that.
- **History.** Servers keep the last 5 versions of every record. The app's
  Sync page lists recent changes and can restore any version, including
  deleted items.

The server stores ciphertext, opaque record keys (HMACs of the record IDs),
hashes of device tokens and wrapped keychains. It learns record counts,
sizes and timing, nothing else.

**Local secrets.** Device keys, the token and the keychain are stored in
SharedPreferences next to the app data they protect, which is unencrypted
there anyway. Platform keystores (`flutter_secure_storage`) would add
packaging dependencies (libsecret on Linux, keychain entitlements on macOS)
for little gain; revisit if the app ever encrypts its local data.

## Backends

| | Sync server | WebDAV |
| --- | --- | --- |
| realtime updates | yes (WebSocket, foreground only) | polls every minute in the foreground |
| version history | 5 per record | no |
| revoked device locked out of storage | yes | no, change the WebDAV password |
| key rotation on revoke | yes | yes |
| pairing code contains | server URL | WebDAV URL **and credentials** |

## Running a server

### Cloudflare Worker (free plan)

```sh
cd worker
bun install
bunx wrangler deploy
```

Set `MAX_VAULT_BYTES` as a variable to change the per-vault quota
(default 64 MiB). Free plan limits that matter: 100k requests/day, 5 GB
total storage. Clients batch writes and debounce edits by 2 seconds.

### Self-hosted (Rust + SQLite)

```sh
docker build -t cu-sync-server server
docker run -d -p 8787:8787 -v cu-sync:/data cu-sync-server
```

Or `cargo run --release` in `server/`. Configuration via environment:

| variable | default |
| --- | --- |
| `CU_SYNC_BIND` | `0.0.0.0:8787` |
| `CU_SYNC_DB` | `sync.db` (`/data/sync.db` in Docker) |
| `CU_SYNC_MAX_VAULT_BYTES` | `67108864` |

Put it behind a TLS reverse proxy (WebSockets must be passed through).

## Testing

```sh
# protocol conformance, against either server
SYNC_URL=http://127.0.0.1:8787 bun test ./conformance

# client unit tests
cd ../chameleonultragui && flutter test test/sync

# end-to-end: create, pair, realtime, history, revoke, recover
SYNC_URL=http://127.0.0.1:8787 flutter test test/sync/service_integration_test.dart
WEBDAV_URL=http://user:pass@127.0.0.1:8080/dav flutter test test/sync/service_integration_test.dart
```

## Abuse limits

Anyone can create a vault, so a public instance is an anonymous blob store.
Both servers cap blob size (1 MiB) and vault size. They do not rate limit;
on Cloudflare add a [rate limiting rule](https://developers.cloudflare.com/waf/rate-limiting-rules/),
for the Rust server use the reverse proxy. Neither expires idle vaults yet.
