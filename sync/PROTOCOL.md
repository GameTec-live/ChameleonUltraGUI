# Chameleon Ultra GUI sync protocol (v1)

End-to-end encrypted settings/data sync. Servers store opaque blobs and never
see plaintext, record IDs or keys. Two server implementations speak this
protocol and must stay feature-identical:

- `worker/` – Cloudflare Worker + Durable Objects (free tier friendly)
- `server/` – self-hostable Rust binary with SQLite

`conformance/` runs the same test suite against either one.

## Encoding conventions

- Binary values in JSON and URLs are **base64url without padding** ("b64").
- IDs (`vaultId`, member IDs, record keys, pairing IDs) match `^[A-Za-z0-9_-]{1,64}$`.
- `hash(x)` = `b64(SHA-256(utf8(x)))`. Tokens are b64 strings; servers store
  only `hash(token)`.
- Errors are `{"error": "<code>"}` with the HTTP status listed per endpoint.

## Keys (client side, for reference)

```
entropy (BIP-39 mnemonic, 128–256 bit)
  vaultId        = b64(HKDF(entropy, "cu-sync/vault-id/v1", 16))
  recovery X25519 seed = HKDF(entropy, "cu-sync/recovery-kx/v1", 32)
  recovery token = b64(HKDF(entropy, "cu-sync/recovery-auth/v1", 32))

device: random X25519 key pair, random 32 byte token (b64), random 16 byte id (b64)

keychain (JSON, wrapped once per member):
  {"keyId": b64(32), "current": N, "epochs": {"1": b64(32), ..., "N": b64(32)}}

record key  = b64(HMAC-SHA256(keyId, utf8("<collection>/<id>")))
```

HKDF is HKDF-SHA256 with an empty salt.

### Wrapped keychain

```
[0x01][ephemeral X25519 public key: 32][nonce: 24][XChaCha20-Poly1305 ciphertext+tag]
key = HKDF(X25519(eph, memberPub), salt = ephPub ‖ memberPub, info = "cu-sync/wrap/v1", 32)
aad = utf8(vaultId + "/" + memberId) ‖ u32be(epoch)
```

### Record blob

```
[0x01][epoch: u32 big endian][nonce: 24][XChaCha20-Poly1305 ciphertext+tag]
key = keychain.epochs[epoch]
aad = utf8(vaultId + "/" + recordKey) ‖ u32be(epoch)
plaintext = gzip(utf8(json {"c": collection, "id": id, "t": hlc, "v": value|null}))
```

`v: null` is a tombstone. The gzip header has no optional fields (flags `0`).
Clients inflate only the first member's deflate stream, ignore the trailer
and anything after it, and drop records that inflate past 16 MiB. Servers read **only** the 5 header bytes (to
enforce the current epoch); everything else is opaque.

## Authentication

`Authorization: Bearer <token>`. The server accepts a request if
`hash(token)` matches a member of the vault. WebSockets pass the token as
`?token=` because browsers cannot set headers on WebSocket requests.

All endpoints live under `/v1/vaults/{vaultId}`. Responses allow CORS from any
origin (the web build needs it; data is encrypted anyway).

## Endpoints

### `POST /init` – create a vault (no auth)

```json
{"epoch": 1, "members": [{"id": "recovery", "kind": "recovery", "tokenHash": "…", "keychain": "…"},
                          {"id": "<deviceId>", "kind": "device", "tokenHash": "…", "keychain": "…"}]}
```

Exactly one member must be `{"id": "recovery", "kind": "recovery"}`.
`201` · `409 exists` · `400 bad_request`

### `GET /keyring` – the caller's own wrapped keychain

`200 {"memberId": "…", "kind": "device", "epoch": 3, "keychain": "…"}` · `401`

### `PUT /keyring` – rotate keys

```json
{"fromEpoch": 2, "epoch": 3, "entries": {"<memberId>": "<keychain>", "recovery": "…"}}
```

Atomic. `fromEpoch` must equal the current epoch, `epoch` must be greater, and
`entries` must cover exactly the current members.
`204` · `409 epoch` · `409 members` (body also contains `"members": [ids]`)

### `GET /members`

`200 {"epoch": 3, "members": [{"id": "…", "kind": "device"}]}`

### `POST /members` – add a device

```json
{"id": "<deviceId>", "kind": "device", "tokenHash": "…", "keychain": "…", "epoch": 3, "pairing": "<pairingId>?"}
```

`epoch` must equal the current epoch. If `pairing` is set, that pairing is
consumed. `201` · `409 epoch` · `409 exists`

### `DELETE /members/{id}` – revoke

The recovery member cannot be revoked (`403 forbidden`). Devices may revoke
themselves. Open sockets of the revoked member are closed with code `4001`.
`204` · `404`

### `GET /changes?since={cursor}`

Records written after `cursor` (start with `0`), ordered by sequence number.

```json
{"records": [{"key": "…", "version": "17", "blob": "…"}], "cursor": "17", "more": false}
```

Pages are limited by count and size; repeat with the returned cursor while
`more` is true. `version` is an opaque string used for compare-and-swap.

### `POST /records` – write records (atomic batch)

```json
{"records": [{"key": "…", "base": "17", "blob": "…"}]}
```

`base` is the version the client last saw for that key (`""` if it never saw
one). If any `base` differs from the server's current version, nothing is
written. Every blob's header epoch must equal the vault's current epoch. The
previous version of each record is moved to its history (5 kept per key).

`200 {"versions": {"<key>": "18"}}` · `409 conflict` (`"keys": […]`) ·
`409 epoch` · `413 too_large` (single blob > 1 MiB) · `507 quota`

### `GET /records/{key}/history`

Current version first, then up to 5 previous versions.
`200 {"versions": [{"version": "18", "blob": "…"}]}`

### Pairing mailbox

Lets an existing device add a new one by QR/code. Pairings expire after 10 minutes.

- `POST /pairings` (member) `{"id": "…", "authHash": "…"}` → `201`
- `POST /pairings/{id}/join` (Bearer = pairing token, i.e. `hash` matches
  `authHash`) `{"request": "<opaque string ≤ 4 KiB>"}` → `202` · `404` · `409 exists`
- `GET /pairings/{id}` (member) → `200 {"request": "…" | null}` · `404`

The request content is client defined: the app seals the device id, name,
public key and token hash with XChaCha20-Poly1305 under
`HKDF(pairingSecret, "cu-sync/pair-box/v1")`, a key the server never sees.
Device public keys only ever travel encrypted (here and in `_devices`
records); that is what stops a server from wrapping a keychain of its own for
a member.

### `GET /ws?token=…` – realtime notifications

Server → client JSON text messages:

| message | meaning |
| --- | --- |
| `{"type": "changed", "cursor": "18"}` | records were written |
| `{"type": "keyring", "epoch": 3}` | keys were rotated |
| `{"type": "members"}` | a member was added or revoked |
| `{"type": "pairing", "id": "…"}` | a pairing request arrived |

Right after connecting, clients send the text `ping` and wait for `pong`;
the `pong` confirms the subscription is live (clients should then pull once to
catch anything written while connecting). Clients keep sending `ping`
periodically as a keepalive (the app uses 45 s) and treat a missing `pong` as
a dead connection; later `pong`s carry no meaning. Close code `4001` means the
member was revoked. Clients are expected to connect only while in use (the app
disconnects in the background) and pull once on every (re)connect.

## Limits

| limit | default |
| --- | --- |
| blob size | 1 MiB |
| vault size (records + history) | 64 MiB |
| history per record | 5 |
| changes page | 500 records or 8 MiB |
| pairing lifetime | 10 minutes |
