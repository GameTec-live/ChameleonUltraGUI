import { Api, SyncError } from "./api";
import {
  b64,
  blobEpoch,
  fingerprint,
  hashToken,
  type Keychain,
  openRecord,
  pairingSecret,
  type Payload,
  publicKey,
  randomBytes,
  recordKey,
  recoveryKeys,
  sealRecord,
  unb64,
  unwrapKeychain,
} from "./crypto";
import { Hlc } from "./hlc";

/** Who this page acts as: the recovery member or a paired device. */
export type Session = { vaultId: string; memberId: string; token: string; seed: string };

/** A live record: `value` is the exact JSON string the app stores. */
export type Item = { collection: string; id: string; value: string; time: string };

/** Vault bookkeeping; it counts only under the current key, as in the app. */
const INTERNAL = new Set(["_devices", "_vault"]);

/** What the server holds for one record key. */
type Entry = { version: string; epoch: number; payload: Payload | null };

const PAIRING_PREFIX = "cusync1:";
const PAIRING_LIFETIME_MS = 10 * 60 * 1000;

export function sessionFromPhrase(phrase: string): Session {
  const { vaultId, token, seed } = recoveryKeys(phrase);
  return { vaultId, memberId: "recovery", token, seed: b64(seed) };
}

/**
 * Joins with a pairing code from the app and waits until a device approves
 * the request. [onWaiting] gets this browser's fingerprint to compare.
 */
export async function joinWithCode(
  code: string,
  name: string,
  base: string,
  onWaiting: (fingerprint: string) => void,
  signal: AbortSignal,
): Promise<Session> {
  const trimmed = code.trim();
  if (!trimmed.startsWith(PAIRING_PREFIX)) throw new SyncError("code");
  // The code also names its storage; a code for any other one fails to join here (404).
  let offer: { v: string; p: string; s: string };
  try {
    offer = JSON.parse(new TextDecoder().decode(unb64(trimmed.slice(PAIRING_PREFIX.length))));
  } catch {
    throw new SyncError("code");
  }
  const secret = pairingSecret(unb64(offer.s));
  const seed = randomBytes(32);
  const pub = publicKey(seed);
  const session: Session = { vaultId: offer.v, memberId: b64(randomBytes(16)), token: b64(randomBytes(32)), seed: b64(seed) };
  const api = new Api(session.vaultId, session.token, base);
  const request = { id: session.memberId, name, pub: b64(pub), tokenHash: hashToken(session.token) };
  await api.join(offer.p, secret.authToken, secret.seal(JSON.stringify(request)));
  onWaiting(fingerprint(pub));

  const deadline = Date.now() + PAIRING_LIFETIME_MS;
  while (Date.now() < deadline) {
    if (signal.aborted) throw new SyncError("cancelled");
    try {
      await api.keyring();
      return session;
    } catch (error) {
      if (!(error instanceof SyncError && error.status === 401)) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new SyncError("expired");
}

/** The decrypted vault: pulls all records and writes single changes back. */
export class Vault {
  private keychain!: Keychain;
  private readonly entries = new Map<string, Entry>();
  private cursor = "0";
  private readonly hlc: Hlc;
  private readonly api: Api;

  private constructor(
    readonly session: Session,
    base: string,
  ) {
    this.api = new Api(session.vaultId, session.token, base);
    // Recovery sessions on several pages must not issue identical timestamps.
    this.hlc = new Hlc(session.memberId === "recovery" ? `web-${b64(randomBytes(6))}` : session.memberId);
  }

  /** Throws SyncError 401 when the vault does not exist or this member was removed. */
  static async open(session: Session, base = ""): Promise<Vault> {
    const vault = new Vault(session, base);
    await vault.loadKeychain();
    await vault.refresh();
    return vault;
  }

  get isDevice() {
    return this.session.memberId !== "recovery";
  }

  private async loadKeychain() {
    const { epoch, keychain } = await this.api.keyring();
    this.keychain = unwrapKeychain(keychain, this.session.vaultId, this.session.memberId, epoch, unb64(this.session.seed));
  }

  /** Pulls everything that changed since the last call. */
  async refresh() {
    let more = true;
    while (more) {
      const page = await this.api.changes(this.cursor);
      for (const { key, version, blob } of page.records) {
        let epoch = 0;
        try {
          epoch = blobEpoch(blob);
        } catch {
          // Malformed: kept only for its version.
        }
        if (epoch > this.keychain.current) await this.loadKeychain();
        const payload = await openRecord(this.keychain, this.session.vaultId, key, blob);
        if (payload) this.hlc.observe(payload.t);
        this.entries.set(key, { version, epoch, payload });
      }
      this.cursor = page.cursor;
      more = page.more;
    }
  }

  /** Live records of a collection. */
  items(collection: string): Item[] {
    const items: Item[] = [];
    for (const { epoch, payload } of this.entries.values()) {
      if (payload?.c !== collection || payload.v === null) continue;
      if (INTERNAL.has(collection) && epoch !== this.keychain.current) continue;
      items.push({ collection, id: payload.id, value: payload.v, time: payload.t });
    }
    return items;
  }

  /**
   * Writes one record (`null` deletes it). Throws SyncError "changed" when
   * another device changed it meanwhile; the vault is refreshed then, so the
   * user can review the newer value first.
   */
  async write(collection: string, id: string, value: string | null) {
    const key = recordKey(this.keychain, collection, id);
    for (let attempt = 0; ; attempt++) {
      const payload: Payload = { c: collection, id, t: this.hlc.next(), v: value };
      const blob = await sealRecord(this.keychain, this.session.vaultId, key, payload);
      try {
        const versions = await this.api.push([{ key, base: this.entries.get(key)?.version ?? "", blob }]);
        this.entries.set(key, { version: versions[key] ?? "", epoch: this.keychain.current, payload });
        return;
      } catch (error) {
        if (!(error instanceof SyncError)) throw error;
        if (error.code === "epoch" && attempt === 0) {
          await this.loadKeychain(); // Keys were rotated: seal under the new one.
          continue;
        }
        if (error.code === "conflict") {
          await this.refresh();
          throw new SyncError("changed");
        }
        throw error;
      }
    }
  }

  /** Removes this browser from the vault (paired devices only). */
  async leave() {
    await this.write("_devices", this.session.memberId, null);
    await this.api.revoke(this.session.memberId);
  }
}
