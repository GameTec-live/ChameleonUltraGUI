// Client cryptography of the sync protocol (../../PROTOCOL.md), byte for byte
// what the app does in `lib/sync/crypto.dart`.
import { xchacha20poly1305 } from "@noble/ciphers/chacha.js";
import { x25519 } from "@noble/curves/ed25519.js";
import { hkdf as nobleHkdf } from "@noble/hashes/hkdf.js";
import { hmac } from "@noble/hashes/hmac.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { randomBytes } from "@noble/hashes/utils.js";
import { mnemonicToEntropy } from "@scure/bip39";
import { wordlist } from "@scure/bip39/wordlists/english.js";

export { randomBytes };

const NONCE = 24;
const TAG = 16;
/** Largest record the app inflates; bigger ones are dropped. */
export const MAX_PLAIN_BYTES = 16 << 20;

export const utf8 = (text: string) => new TextEncoder().encode(text);
const fromUtf8 = (bytes: Uint8Array) => new TextDecoder("utf-8", { fatal: true }).decode(bytes);

/** base64url without padding, the protocol's binary encoding. */
export function b64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function unb64(text: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) throw new Error("Invalid base64url");
  return Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));
}

const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
};

const u32 = (value: number) => {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, value);
  return out;
};

const aad = (vaultId: string, id: string, epoch: number) => concat(utf8(`${vaultId}/${id}`), u32(epoch));

const hkdf = (ikm: Uint8Array, info: string, length: number, salt?: Uint8Array) =>
  nobleHkdf(sha256, ikm, salt, utf8(info), length);

/** `hash(x)`: what servers store instead of bearer tokens. */
export const hashToken = (token: string) => b64(sha256(utf8(token)));

export const publicKey = (seed: Uint8Array) => x25519.getPublicKey(seed);

/** Everything derived from a recovery phrase. Throws on unknown words or a bad checksum. */
export function recoveryKeys(phrase: string) {
  const entropy = mnemonicToEntropy(phrase.trim().toLowerCase().split(/\s+/).join(" "), wordlist);
  return {
    vaultId: b64(hkdf(entropy, "cu-sync/vault-id/v1", 16)),
    token: b64(hkdf(entropy, "cu-sync/recovery-auth/v1", 32)),
    seed: hkdf(entropy, "cu-sync/recovery-kx/v1", 32),
  };
}

/** The vault secrets: a stable key for record key obfuscation and one data key per epoch. */
export type Keychain = { keyId: Uint8Array; current: number; epochs: Map<number, Uint8Array> };

type KeychainJson = { keyId: string; current: number; epochs: Record<string, string> };

/** Opens a keychain wrapped for this member; [epoch] is what the server claims (authenticated). */
export function unwrapKeychain(wrapped: string, vaultId: string, memberId: string, epoch: number, seed: Uint8Array): Keychain {
  const bytes = unb64(wrapped);
  if (bytes.length < 1 + 32 + NONCE + TAG || bytes[0] !== 1) throw new Error("Malformed keychain");
  const ephemeral = bytes.subarray(1, 33);
  const key = hkdf(x25519.getSharedSecret(seed, ephemeral), "cu-sync/wrap/v1", 32, concat(ephemeral, publicKey(seed)));
  const plain = xchacha20poly1305(key, bytes.subarray(33, 33 + NONCE), aad(vaultId, memberId, epoch)).decrypt(
    bytes.subarray(33 + NONCE),
  );
  const json = JSON.parse(fromUtf8(plain)) as KeychainJson;
  if (json.current !== epoch) throw new Error("Keychain epoch mismatch");
  return {
    keyId: unb64(json.keyId),
    current: json.current,
    epochs: new Map(Object.entries(json.epochs).map(([e, k]) => [Number(e), unb64(k)])),
  };
}

/** Encrypts a keychain to a member's public key (only used to set up test vaults). */
export function wrapKeychain(keychain: Keychain, vaultId: string, memberId: string, memberPublic: Uint8Array): string {
  const ephemeral = randomBytes(32);
  const ephemeralPublic = publicKey(ephemeral);
  const key = hkdf(
    x25519.getSharedSecret(ephemeral, memberPublic),
    "cu-sync/wrap/v1",
    32,
    concat(ephemeralPublic, memberPublic),
  );
  const json: KeychainJson = {
    keyId: b64(keychain.keyId),
    current: keychain.current,
    epochs: Object.fromEntries([...keychain.epochs].map(([e, k]) => [String(e), b64(k)])),
  };
  const nonce = randomBytes(NONCE);
  const box = xchacha20poly1305(key, nonce, aad(vaultId, memberId, keychain.current)).encrypt(utf8(JSON.stringify(json)));
  return b64(concat(new Uint8Array([1]), ephemeralPublic, nonce, box));
}

/** The opaque server-side key of a record. */
export const recordKey = (keychain: Keychain, collection: string, id: string) =>
  b64(hmac(sha256, keychain.keyId, utf8(`${collection}/${id}`)));

/** The epoch in a blob header (the only part servers read). */
export function blobEpoch(blob: Uint8Array): number {
  if (blob.length < 5 + NONCE + TAG || blob[0] !== 1) throw new Error("Malformed blob");
  return new DataView(blob.buffer, blob.byteOffset).getUint32(1);
}

/** What a record blob holds: `v` is the exact JSON string the app stores, null for a deletion. */
export type Payload = { c: string; id: string; t: string; v: string | null };

/** `[0x01][u32 epoch][nonce][ciphertext+tag]` of the gzipped payload, under the current epoch. */
export async function sealRecord(keychain: Keychain, vaultId: string, key: string, payload: Payload): Promise<Uint8Array> {
  const nonce = randomBytes(NONCE);
  const data = keychain.epochs.get(keychain.current)!;
  const box = xchacha20poly1305(data, nonce, aad(vaultId, key, keychain.current)).encrypt(
    await gzip(utf8(JSON.stringify(payload))),
  );
  return concat(new Uint8Array([1]), u32(keychain.current), nonce, box);
}

/** Opens a record blob; null if it is not a valid record for [key] (foreign or tampered data is ignored). */
export async function openRecord(keychain: Keychain, vaultId: string, key: string, blob: Uint8Array): Promise<Payload | null> {
  try {
    const epoch = blobEpoch(blob);
    const data = keychain.epochs.get(epoch);
    if (!data) return null;
    const plain = xchacha20poly1305(data, blob.subarray(5, 5 + NONCE), aad(vaultId, key, epoch)).decrypt(
      blob.subarray(5 + NONCE),
    );
    const payload = JSON.parse(fromUtf8(await gunzip(plain))) as Payload;
    // A blob only counts for the record key it was encrypted for.
    return recordKey(keychain, payload.c, payload.id) === key ? payload : null;
  } catch {
    return null;
  }
}

async function gzip(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data as BlobPart]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Inflates at most MAX_PLAIN_BYTES, so a vault member cannot exhaust memory with a decompression bomb. */
async function gunzip(data: Uint8Array): Promise<Uint8Array> {
  const reader = new Blob([data as BlobPart]).stream().pipeThrough(new DecompressionStream("gzip")).getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return concat(...chunks);
    size += value.length;
    if (size > MAX_PLAIN_BYTES) {
      await reader.cancel();
      throw new Error("Record too large");
    }
    chunks.push(value);
  }
}

/** The one-time secret behind a pairing code. */
export function pairingSecret(secret: Uint8Array) {
  const boxKey = hkdf(secret, "cu-sync/pair-box/v1", 32);
  return {
    authToken: b64(hkdf(secret, "cu-sync/pair-auth/v1", 32)),
    seal(request: string): string {
      const nonce = randomBytes(NONCE);
      return b64(concat(nonce, xchacha20poly1305(boxKey, nonce).encrypt(utf8(request))));
    },
    open(sealed: string): string {
      const bytes = unb64(sealed);
      return fromUtf8(xchacha20poly1305(boxKey, bytes.subarray(0, NONCE)).decrypt(bytes.subarray(NONCE)));
    },
  };
}

/** Short human-comparable fingerprint of a public key, as the approving device shows it. */
export const fingerprint = (pub: Uint8Array) =>
  Array.from(sha256(pub).subarray(0, 6), (b) => b.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase()
    .replace(/(.{4})(?!$)/g, "$1-");
