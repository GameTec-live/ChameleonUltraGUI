import { DurableObject } from "cloudflare:workers";
import { ApiError, b64decode, b64encode, hashToken, json, parseJson, validId } from "./util";

export interface Env {
  VAULTS: DurableObjectNamespace<Vault>;
  /** Optional override of the per-vault storage quota in bytes. */
  MAX_VAULT_BYTES?: string;
}

const LIMITS = {
  blobBytes: 1 << 20,
  history: 5,
  pageRecords: 500,
  pageBytes: 8 << 20,
  pairingMs: 10 * 60 * 1000,
  defaultVaultBytes: 64 << 20,
};

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault (id INTEGER PRIMARY KEY CHECK (id = 1), epoch INTEGER NOT NULL, seq INTEGER NOT NULL, bytes INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS members (id TEXT PRIMARY KEY, kind TEXT NOT NULL, token_hash TEXT NOT NULL, keychain TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS members_token ON members (token_hash);
CREATE TABLE IF NOT EXISTS records (key TEXT PRIMARY KEY, seq INTEGER NOT NULL, blob BLOB NOT NULL);
CREATE INDEX IF NOT EXISTS records_seq ON records (seq);
CREATE TABLE IF NOT EXISTS history (key TEXT NOT NULL, seq INTEGER NOT NULL, blob BLOB NOT NULL, PRIMARY KEY (key, seq));
CREATE TABLE IF NOT EXISTS pairings (id TEXT PRIMARY KEY, auth_hash TEXT NOT NULL, request TEXT, expires INTEGER NOT NULL);
`;

type Member = { id: string; kind: string };
type VaultRow = { epoch: number; seq: number; bytes: number };
type MemberInput = { id: string; kind: string; tokenHash: string; keychain: string };

/** Reads the epoch from a record blob header: `[0x01][u32 BE epoch]…`. */
function blobEpoch(blob: Uint8Array): number | null {
  // Header (5) + nonce (24) + Poly1305 tag (16) is the smallest valid blob.
  if (blob.length < 45 || blob[0] !== 1) return null;
  return new DataView(blob.buffer, blob.byteOffset).getUint32(1);
}

function validMember(m: unknown): MemberInput {
  const { id, kind, tokenHash, keychain } = (m ?? {}) as Record<string, unknown>;
  if (kind !== "recovery" && kind !== "device") throw ApiError.badRequest();
  if (
    // The recovery member always has the id "recovery"; devices never do.
    (kind === "recovery") !== (id === "recovery") ||
    !validId(id) ||
    !validId(tokenHash) ||
    typeof keychain !== "string" ||
    keychain.length === 0 ||
    keychain.length > 8192
  ) {
    throw ApiError.badRequest();
  }
  return { id, kind, tokenHash, keychain };
}

/** One Durable Object per vault, addressed by `idFromName(vaultId)`. */
export class Vault extends DurableObject<Env> {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(SCHEMA);
    // Answered by the runtime without waking the object from hibernation.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request: Request): Promise<Response> {
    try {
      return await this.route(request);
    } catch (error) {
      if (error instanceof ApiError) return json(error.body, error.status);
      console.error(error);
      return json({ error: "internal" }, 500);
    }
  }

  private async route(request: Request): Promise<Response> {
    const url = new URL(request.url);
    // /v1/vaults/{vault}/{...rest}
    const [, , , , ...rest] = url.pathname.split("/");
    const path = rest.join("/");
    const method = request.method;

    if (method === "POST" && path === "init") return this.init(await parseJson(request));

    // Pairing join authenticates with the pairing token, not a member token.
    const join = path.match(/^pairings\/([^/]+)\/join$/);
    if (method === "POST" && join) return this.joinPairing(join[1]!, request);

    if (path === "ws") {
      const member = await this.authenticate(url.searchParams.get("token"));
      if (request.headers.get("Upgrade") !== "websocket") throw ApiError.badRequest();
      const { 0: client, 1: server } = new WebSocketPair();
      this.ctx.acceptWebSocket(server, [member.id]);
      return new Response(null, { status: 101, webSocket: client });
    }

    const auth = request.headers.get("Authorization");
    const member = await this.authenticate(auth?.startsWith("Bearer ") ? auth.slice(7) : null);

    if (path === "keyring" && method === "GET") return this.keyring(member);
    if (path === "keyring" && method === "PUT") return this.rotate(await parseJson(request));
    if (path === "members" && method === "GET") return this.members();
    if (path === "members" && method === "POST") return this.addMember(await parseJson(request));
    const memberPath = path.match(/^members\/([^/]+)$/);
    if (memberPath && method === "DELETE") return this.revoke(memberPath[1]!);
    if (path === "changes" && method === "GET") return this.changes(url.searchParams.get("since") ?? "0");
    if (path === "records" && method === "POST") return this.write(await parseJson(request));
    const history = path.match(/^records\/([^/]+)\/history$/);
    if (history && method === "GET") return this.history(history[1]!);
    if (path === "pairings" && method === "POST") return this.openPairing(await parseJson(request));
    const pairing = path.match(/^pairings\/([^/]+)$/);
    if (pairing && method === "GET") return this.pairing(pairing[1]!);
    throw ApiError.notFound();
  }

  private vault(): VaultRow {
    const row = this.sql.exec<VaultRow>("SELECT epoch, seq, bytes FROM vault").toArray()[0];
    if (!row) throw ApiError.notFound();
    return row;
  }

  private async authenticate(token: string | null): Promise<Member> {
    if (!token) throw ApiError.unauthorized();
    const hash = await hashToken(token);
    const member = this.sql
      .exec<Member>("SELECT id, kind FROM members WHERE token_hash = ?", hash)
      .toArray()[0];
    if (!member) throw ApiError.unauthorized();
    return member;
  }

  private broadcast(message: object) {
    const text = JSON.stringify(message);
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(text);
      } catch {
        // Socket already closing; nothing to do.
      }
    }
  }

  private memberList(): Member[] {
    return this.sql.exec<Member>("SELECT id, kind FROM members ORDER BY id").toArray();
  }

  private insertMember(m: MemberInput) {
    if (this.sql.exec("SELECT 1 FROM members WHERE id = ?", m.id).toArray().length) {
      throw ApiError.conflict("exists");
    }
    this.sql.exec(
      "INSERT INTO members (id, kind, token_hash, keychain) VALUES (?, ?, ?, ?)",
      m.id,
      m.kind,
      m.tokenHash,
      m.keychain,
    );
  }

  private init(body: { epoch?: unknown; members?: unknown }): Response {
    if (!Array.isArray(body.members) || typeof body.epoch !== "number" || body.epoch < 1) {
      throw ApiError.badRequest();
    }
    const members = body.members.map(validMember);
    if (members.filter((m) => m.kind === "recovery").length !== 1) throw ApiError.badRequest();
    this.ctx.storage.transactionSync(() => {
      if (this.sql.exec("SELECT 1 FROM vault").toArray().length) throw ApiError.conflict("exists");
      this.sql.exec("INSERT INTO vault (id, epoch, seq, bytes) VALUES (1, ?, 0, 0)", body.epoch);
      members.forEach((m) => this.insertMember(m));
    });
    return new Response(null, { status: 201 });
  }

  private keyring(member: Member): Response {
    const { epoch } = this.vault();
    const { keychain } = this.sql
      .exec<{ keychain: string }>("SELECT keychain FROM members WHERE id = ?", member.id)
      .one();
    return json({ memberId: member.id, kind: member.kind, epoch, keychain });
  }

  private rotate(body: { fromEpoch?: unknown; epoch?: unknown; entries?: unknown }): Response {
    const { fromEpoch, epoch, entries } = body;
    if (typeof fromEpoch !== "number" || typeof epoch !== "number" || typeof entries !== "object" || !entries) {
      throw ApiError.badRequest();
    }
    const keychains = Object.entries(entries as Record<string, unknown>);
    if (keychains.some(([id, k]) => !validId(id) || typeof k !== "string")) throw ApiError.badRequest();
    this.ctx.storage.transactionSync(() => {
      if (this.vault().epoch !== fromEpoch || epoch <= fromEpoch) throw ApiError.conflict("epoch");
      const ids = this.memberList().map((m) => m.id);
      const given = new Set(keychains.map(([id]) => id));
      if (ids.length !== given.size || ids.some((id) => !given.has(id))) {
        throw new ApiError(409, { error: "members", members: ids });
      }
      for (const [id, keychain] of keychains) {
        this.sql.exec("UPDATE members SET keychain = ? WHERE id = ?", keychain as string, id);
      }
      this.sql.exec("UPDATE vault SET epoch = ?", epoch);
    });
    this.broadcast({ type: "keyring", epoch });
    return new Response(null, { status: 204 });
  }

  private members(): Response {
    return json({ epoch: this.vault().epoch, members: this.memberList() });
  }

  private addMember(body: { epoch?: unknown; pairing?: unknown } & Record<string, unknown>): Response {
    const member = validMember(body);
    const { pairing } = body;
    if (member.kind !== "device" || (pairing !== undefined && pairing !== null && !validId(pairing))) {
      throw ApiError.badRequest();
    }
    this.ctx.storage.transactionSync(() => {
      if (this.vault().epoch !== body.epoch) throw ApiError.conflict("epoch");
      this.insertMember(member);
      if (pairing) this.sql.exec("DELETE FROM pairings WHERE id = ?", pairing);
    });
    this.broadcast({ type: "members" });
    return new Response(null, { status: 201 });
  }

  private revoke(id: string): Response {
    if (!validId(id)) throw ApiError.badRequest();
    if (id === "recovery") throw ApiError.forbidden();
    if (this.sql.exec("DELETE FROM members WHERE id = ?", id).rowsWritten === 0) throw ApiError.notFound();
    for (const ws of this.ctx.getWebSockets(id)) ws.close(4001, "revoked");
    this.broadcast({ type: "members" });
    return new Response(null, { status: 204 });
  }

  private changes(sinceParam: string): Response {
    if (!/^\d+$/.test(sinceParam)) throw ApiError.badRequest();
    const since = Number(sinceParam);
    const rows = this.sql.exec<{ key: string; seq: number; blob: ArrayBuffer }>(
      "SELECT key, seq, blob FROM records WHERE seq > ? ORDER BY seq LIMIT ?",
      since,
      LIMITS.pageRecords + 1,
    );
    const records: { key: string; version: string; blob: string }[] = [];
    let bytes = 0;
    let more = false;
    let cursor = since;
    for (const row of rows) {
      // Always return at least one record so a cursor can never stall.
      if (
        records.length === LIMITS.pageRecords ||
        (records.length > 0 && bytes + row.blob.byteLength > LIMITS.pageBytes)
      ) {
        more = true;
        break;
      }
      bytes += row.blob.byteLength;
      cursor = row.seq;
      records.push({ key: row.key, version: String(row.seq), blob: b64encode(new Uint8Array(row.blob)) });
    }
    return json({ records, cursor: String(cursor), more });
  }

  private write(body: { records?: unknown }): Response {
    if (!Array.isArray(body.records) || body.records.length === 0) throw ApiError.badRequest();
    const records = body.records.map((r: unknown) => {
      const { key, base, blob } = (r ?? {}) as Record<string, unknown>;
      if (!validId(key) || typeof base !== "string" || typeof blob !== "string") throw ApiError.badRequest();
      const bytes = b64decode(blob);
      if (bytes.length > LIMITS.blobBytes) throw ApiError.tooLarge();
      return { key, base, blob: bytes };
    });
    const maxBytes = Number(this.env.MAX_VAULT_BYTES ?? LIMITS.defaultVaultBytes);

    const { versions, cursor } = this.ctx.storage.transactionSync(() => {
      let { epoch, seq, bytes } = this.vault();
      const conflicts: string[] = [];
      for (const { key, base, blob } of records) {
        const header = blobEpoch(blob);
        if (header === null) throw ApiError.badRequest();
        if (header !== epoch) throw ApiError.conflict("epoch");
        const current = this.sql.exec<{ seq: number }>("SELECT seq FROM records WHERE key = ?", key).toArray()[0];
        if ((current ? String(current.seq) : "") !== base) conflicts.push(key);
      }
      if (conflicts.length) throw new ApiError(409, { error: "conflict", keys: conflicts });

      const versions: Record<string, string> = {};
      for (const { key, blob } of records) {
        seq += 1;
        // Move the previous version into history, then prune it to the limit.
        this.sql.exec("INSERT INTO history (key, seq, blob) SELECT key, seq, blob FROM records WHERE key = ?", key);
        const pruned = this.sql
          .exec<{ seq: number; size: number }>(
            "SELECT seq, length(blob) AS size FROM history WHERE key = ? ORDER BY seq DESC LIMIT -1 OFFSET ?",
            key,
            LIMITS.history,
          )
          .toArray();
        for (const old of pruned) {
          this.sql.exec("DELETE FROM history WHERE key = ? AND seq = ?", key, old.seq);
          bytes -= old.size;
        }
        this.sql.exec(
          "INSERT INTO records (key, seq, blob) VALUES (?1, ?2, ?3) ON CONFLICT (key) DO UPDATE SET seq = ?2, blob = ?3",
          key,
          seq,
          blob,
        );
        bytes += blob.length;
        versions[key] = String(seq);
      }
      if (bytes > maxBytes) throw new ApiError(507, { error: "quota" });
      this.sql.exec("UPDATE vault SET seq = ?, bytes = ?", seq, bytes);
      return { versions, cursor: String(seq) };
    });
    this.broadcast({ type: "changed", cursor });
    return json({ versions });
  }

  private history(key: string): Response {
    if (!validId(key)) throw ApiError.badRequest();
    const rows = this.sql.exec<{ seq: number; blob: ArrayBuffer }>(
      "SELECT seq, blob FROM records WHERE key = ?1 UNION ALL SELECT seq, blob FROM history WHERE key = ?1 ORDER BY seq DESC",
      key,
    );
    const versions = [...rows].map((r) => ({ version: String(r.seq), blob: b64encode(new Uint8Array(r.blob)) }));
    return json({ versions });
  }

  private openPairing(body: { id?: unknown; authHash?: unknown }): Response {
    const { id, authHash } = body;
    if (!validId(id) || !validId(authHash)) throw ApiError.badRequest();
    this.sql.exec("DELETE FROM pairings WHERE expires < ?", Date.now());
    if (this.sql.exec("SELECT 1 FROM pairings WHERE id = ?", id).toArray().length) throw ApiError.conflict("exists");
    this.sql.exec(
      "INSERT INTO pairings (id, auth_hash, expires) VALUES (?, ?, ?)",
      id,
      authHash,
      Date.now() + LIMITS.pairingMs,
    );
    return new Response(null, { status: 201 });
  }

  private async joinPairing(id: string, request: Request): Promise<Response> {
    if (!validId(id)) throw ApiError.badRequest();
    const auth = request.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) throw ApiError.unauthorized();
    const hash = await hashToken(auth.slice(7));
    const body = await parseJson<{ request?: unknown }>(request);
    if (typeof body.request !== "string") throw ApiError.badRequest();
    if (body.request.length > 4096) throw ApiError.tooLarge();

    const pairing = this.sql
      .exec<{ auth_hash: string; request: string | null }>(
        "SELECT auth_hash, request FROM pairings WHERE id = ? AND expires >= ?",
        id,
        Date.now(),
      )
      .toArray()[0];
    if (!pairing) throw ApiError.notFound();
    if (pairing.auth_hash !== hash) throw ApiError.unauthorized();
    if (pairing.request !== null) throw ApiError.conflict("exists");
    this.sql.exec("UPDATE pairings SET request = ? WHERE id = ?", body.request, id);
    this.broadcast({ type: "pairing", id });
    return new Response(null, { status: 202 });
  }

  private pairing(id: string): Response {
    if (!validId(id)) throw ApiError.badRequest();
    const pairing = this.sql
      .exec<{ request: string | null }>("SELECT request FROM pairings WHERE id = ? AND expires >= ?", id, Date.now())
      .toArray()[0];
    if (!pairing) throw ApiError.notFound();
    return json({ request: pairing.request });
  }

  async webSocketClose(ws: WebSocket) {
    try {
      ws.close(1000);
    } catch {
      // Already closed (the runtime may auto-reply to close frames).
    }
  }
}
