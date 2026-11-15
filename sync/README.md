# Sync

End-to-end encrypted sync of settings, saved cards, dictionaries and plugins
between Chameleon Ultra GUI installs. No accounts: a vault is identified by its
recovery phrase, devices by their own keys.

| folder | what |
| --- | --- |
| [`PROTOCOL.md`](PROTOCOL.md) | wire protocol + crypto formats (the contract) |
| `worker/` | Cloudflare Worker + SQLite Durable Objects, runs on the free plan |
| `server/` | self-hostable Rust server, single SQLite file |
| `web/` | web app both servers serve at `/` (React + Vite) |
| `conformance/` | protocol test suite, runs against either server |
| `../chameleonultragui/lib/sync/` | client: engine, crypto, backends |

The app also syncs to any **WebDAV** folder (Nextcloud, ownCloud, rclone, …)
without a sync server; see [Backends](#backends) for what that gives up. It
detects changes by ETag, so the server's ETags must change on every write
(true for Nextcloud and Apache; servers deriving them from second-granularity
mtime and size, like wsgidav, can miss same-size rewrites within a second).

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

## Web app

Both servers serve a web app at `/` for looking into a vault from any
browser. It signs in like the app: with the recovery phrase (kept only until
the page closes), or with a pairing code, which makes the browser a device
until "Sign out" removes it again. Records are decrypted in the page; the
server still only sees ciphertext. It can:

- browse cards, dictionaries, folders, settings, plugins and devices
- edit any record as JSON, or delete it (synced to all devices)
- export everything as the app's settings file (Settings → Import settings),
  a card as `.json`, a dictionary as `.dic` and a folder in the app's folder
  format

The page loads no third-party code and sends a strict Content Security
Policy. `cd web && bun run dev` serves it with hot reload against a server
on port 8787.

## Backends

| | Sync server | WebDAV |
| --- | --- | --- |
| realtime updates | yes (WebSocket, foreground only) | polls every minute in the foreground |
| version history | 5 per record | no |
| revoked device locked out of storage | yes | no: change the WebDAV password, or it can still tamper with data and keys |
| key rotation on revoke | yes | yes |
| pairing code contains | server URL | WebDAV URL **and credentials** |

## Running a server

The app presets `https://sync.gametec-live.com` as the sync server; users can
enter any other one. To ship a build with a different preset (or none, with an
empty value), pass it at build time:

```sh
flutter build <platform> --dart-define=SYNC_SERVER_URL=https://sync.example.com
```

### Cloudflare Worker (free plan)

```sh
cd worker
bun install
bunx wrangler deploy
```

`wrangler deploy` (and `wrangler dev`) build the web app first and upload it
as static assets, which do not count against the Worker's request limits.
Vaults unused (no authenticated request) for 30 days are deleted; a vault
stays while a device is connected. `NOTICE` in `wrangler.jsonc` is shown in
the app before setup: say who runs the instance and keep the expiry note.
Set `MAX_VAULT_BYTES` as a variable to change the per-vault quota
(default 64 MiB). Each client address gets 300 requests and 3 new vaults per
minute (`ratelimits` in `wrangler.jsonc`). Free plan limits that matter: 100k requests/day, 5 GB
total storage. Clients batch writes and debounce edits by 2 seconds.

### Self-hosted (Rust + SQLite)

CI publishes the image for amd64 and arm64 as
`ghcr.io/gametec-live/cu-sync-server` (`latest` follows `main`).
[`server/compose.yaml`](server/compose.yaml) runs it with a persistent volume:

```sh
cd server && docker compose up -d
```

To build the image yourself:

```sh
docker build -t cu-sync-server -f server/Dockerfile .
docker run -d -p 8787:8787 -v cu-sync:/data cu-sync-server
```

Or build the web app first (`bun install && bun run build` in `web/`; the
binary embeds it), then `cargo run --release` in `server/`. Configuration via
environment:

| variable | default |
| --- | --- |
| `CU_SYNC_BIND` | `0.0.0.0:8787` |
| `CU_SYNC_DB` | `sync.db` (`/data/sync.db` in Docker) |
| `CU_SYNC_MAX_VAULT_BYTES` | `67108864` |
| `CU_SYNC_NOTICE` | none; shown in the app before setup (who runs it, ...) |
| `CU_SYNC_RATE_LIMIT` | `on`: 300 requests per minute and 5 new vaults per hour per client; `double` or `off` |
| `CU_SYNC_PROXY` | `none`; `forwarded` trusts the last `X-Forwarded-For` entry, `cloudflare` trusts `CF-Connecting-IP` (proxied DNS or Cloudflare Tunnel) |
| `CU_SYNC_SIGNUP_TOKEN` | none; when set, creating a vault needs this token (the app asks for it) |
| `CU_SYNC_SIGNUP` | `open`; `closed` stops new vaults (existing ones keep working, devices can still join) |

Put it behind a TLS reverse proxy (WebSockets must be passed through) and set
`CU_SYNC_PROXY` to match, or every client shares the proxy's limit. Only set
it when the server is unreachable except through that proxy: anyone talking
to it directly could forge the header. IPv6 clients are limited per /64.

## Testing

```sh
# protocol conformance, against either server, with rate limits off
# (CU_SYNC_RATE_LIMIT=off cargo run, or wrangler dev --var RATE_LIMIT:off)
SYNC_URL=http://127.0.0.1:8787 bun test ./conformance

# web app: crypto against fixtures written by the app's crypto, export formats
cd web && bun test src

# client unit tests
cd ../chameleonultragui && flutter test test/sync

# end-to-end: create, pair, realtime, history, revoke, recover
SYNC_URL=http://127.0.0.1:8787 flutter test test/sync/service_integration_test.dart
WEBDAV_URL=http://user:pass@127.0.0.1:8080/dav flutter test test/sync/service_integration_test.dart
```

## Abuse limits

Anyone can create a vault on an open instance, so it is an anonymous blob
store. Both servers cap blob size (1 MiB) and vault size and rate limit per
client address. The Worker deletes vaults unused for 30 days; the Rust server
keeps them, but private instances can require a signup token or close signup
once their vaults exist. The Worker's limits are per Cloudflare location and
only for a minute at most, so treat them as a coarse filter.
