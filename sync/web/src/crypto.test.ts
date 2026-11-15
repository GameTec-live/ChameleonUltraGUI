import { describe, expect, test } from "bun:test";
import { xchacha20poly1305 } from "@noble/ciphers/chacha.js";
import fixture from "./dart-fixture.json";
import {
  fingerprint,
  openRecord,
  pairingSecret,
  publicKey,
  recordKey,
  recoveryKeys,
  sealRecord,
  unb64,
  unwrapKeychain,
} from "./crypto";

// dart-fixture.json was written by the app's lib/sync/crypto.dart: a vault
// with a keychain at epoch 2, one sealed card and a sealed pairing request.
describe("reads what the app writes", () => {
  const keys = recoveryKeys(fixture.phrase);
  const keychain = unwrapKeychain(fixture.keychain, fixture.vaultId, "recovery", fixture.epoch, keys.seed);

  test("recovery phrase", () => {
    expect([keys.vaultId, keys.token]).toEqual([fixture.vaultId, fixture.token]);
    expect(fingerprint(publicKey(keys.seed))).toBe(fixture.fingerprint);
    expect(() => recoveryKeys(fixture.phrase.replace("abandon", "ability"))).toThrow();
  });

  test("keychain and records", async () => {
    expect(keychain.current).toBe(2);
    expect(recordKey(keychain, "cards", "c1")).toBe(fixture.recordKey);
    expect(await openRecord(keychain, fixture.vaultId, fixture.recordKey, unb64(fixture.blob))).toEqual(fixture.payload);
    // A blob only counts for the key it was sealed for.
    expect(await openRecord(keychain, fixture.vaultId, "other", unb64(fixture.blob))).toBeNull();
  });

  test("pairing", () => {
    const secret = pairingSecret(unb64(fixture.pairingSecret));
    expect(secret.authToken).toBe(fixture.pairingAuth);
    expect(secret.open(fixture.pairingSealed)).toBe('{"id":"d1"}');
    expect(secret.open(secret.seal("request"))).toBe("request");
  });

  test("written records open again and use the gzip header the app accepts", async () => {
    const payload = { c: "settings", id: "app_theme", t: "000001700000000-000001-web", v: "2" };
    const key = recordKey(keychain, payload.c, payload.id);
    const blob = await sealRecord(keychain, fixture.vaultId, key, payload);
    expect(await openRecord(keychain, fixture.vaultId, key, blob)).toEqual(payload);
    const aad = new Uint8Array([...new TextEncoder().encode(`${fixture.vaultId}/${key}`), 0, 0, 0, 2]);
    const gzipped = xchacha20poly1305(keychain.epochs.get(2)!, blob.subarray(5, 29), aad).decrypt(blob.subarray(29));
    // lib/sync/engine.dart `_inflate`: magic, deflate, no optional fields.
    expect([...gzipped.subarray(0, 4)]).toEqual([0x1f, 0x8b, 8, 0]);
  });
});
