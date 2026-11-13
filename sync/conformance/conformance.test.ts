// Protocol conformance suite for sync servers (see ../PROTOCOL.md).
// Usage: SYNC_URL=http://localhost:8787 bun test ./conformance
import { describe, expect, test } from "bun:test";

const base = process.env.SYNC_URL ?? "http://localhost:8787";

const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const randomId = () => b64(crypto.getRandomValues(new Uint8Array(16)));
const hash = async (token: string) =>
  b64(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))));

/** A structurally valid record blob: servers only read the 5 byte header. */
function blob(epoch: number, size = 64): string {
  const bytes = crypto.getRandomValues(new Uint8Array(size));
  bytes[0] = 1;
  new DataView(bytes.buffer).setUint32(1, epoch);
  return b64(bytes);
}

type Vault = Awaited<ReturnType<typeof createVault>>;

async function createVault() {
  const id = randomId();
  const recovery = randomId();
  const device = { id: randomId(), token: randomId() };
  const call = async (method: string, path: string, token?: string, body?: unknown) => {
    const response = await fetch(`${base}/v1/vaults/${id}/${path}`, {
      method,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null };
  };
  const init = await call("POST", "init", undefined, {
    epoch: 1,
    members: [
      { id: "recovery", kind: "recovery", tokenHash: await hash(recovery), keychain: "r1" },
      { id: device.id, kind: "device", tokenHash: await hash(device.token), keychain: "d1" },
    ],
  });
  expect(init.status).toBe(201);
  return { id, recovery, device, call, as: (token: string) => ({
    get: (path: string) => call("GET", path, token),
    post: (path: string, body?: unknown) => call("POST", path, token, body),
    put: (path: string, body: unknown) => call("PUT", path, token, body),
    del: (path: string) => call("DELETE", path, token),
  }) };
}

async function addDevice(vault: Vault, epoch = 1) {
  const device = { id: randomId(), token: randomId() };
  const result = await vault.as(vault.device.token).post("members", {
    id: device.id, kind: "device", tokenHash: await hash(device.token), keychain: "k", epoch,
  });
  expect(result.status).toBe(201);
  return device;
}

describe("vault setup and auth", () => {
  test("init is once only and needs exactly one recovery member", async () => {
    const vault = await createVault();
    const again = await vault.call("POST", "init", undefined, { epoch: 1, members: [] });
    expect(again.status).toBe(400);
    const dup = await vault.call("POST", "init", undefined, {
      epoch: 1, members: [{ id: "recovery", kind: "recovery", tokenHash: "x", keychain: "k" }],
    });
    expect(dup).toEqual({ status: 409, body: { error: "exists" } });
  });

  test("keyring returns the caller's own entry", async () => {
    const vault = await createVault();
    expect((await vault.as(vault.device.token).get("keyring")).body).toEqual({
      memberId: vault.device.id, kind: "device", epoch: 1, keychain: "d1",
    });
    expect((await vault.as(vault.recovery).get("keyring")).body.keychain).toBe("r1");
    expect((await vault.as("wrong").get("keyring")).status).toBe(401);
    expect((await vault.call("GET", "keyring")).status).toBe(401);
  });

  test("members lists everyone with the epoch", async () => {
    const vault = await createVault();
    const { body } = await vault.as(vault.device.token).get("members");
    expect(body.epoch).toBe(1);
    expect(body.members).toHaveLength(2);
    expect(body.members).toContainEqual({ id: "recovery", kind: "recovery" });
  });
});

describe("records", () => {
  test("write, pull and compare-and-swap", async () => {
    const vault = await createVault();
    const api = vault.as(vault.device.token);
    const write = await api.post("records", { records: [{ key: "a", base: "", blob: blob(1) }, { key: "b", base: "", blob: blob(1) }] });
    expect(write.status).toBe(200);
    const versionA = write.body.versions.a;

    const changes = await api.get("changes?since=0");
    expect(changes.body.records.map((r: { key: string }) => r.key)).toEqual(["a", "b"]);
    expect(changes.body.more).toBe(false);
    expect((await api.get(`changes?since=${changes.body.cursor}`)).body.records).toEqual([]);

    // Batches are atomic: one stale base rejects the whole write.
    const stale = await api.post("records", { records: [{ key: "a", base: versionA, blob: blob(1) }, { key: "b", base: "", blob: blob(1) }] });
    expect(stale).toEqual({ status: 409, body: { error: "conflict", keys: ["b"] } });
    expect((await api.get(`changes?since=${changes.body.cursor}`)).body.records).toEqual([]);

    const ok = await api.post("records", { records: [{ key: "a", base: versionA, blob: blob(1) }] });
    expect(ok.status).toBe(200);
    expect(Number(ok.body.versions.a)).toBeGreaterThan(Number(versionA));
  });

  test("rejects foreign epochs, malformed and oversized blobs", async () => {
    const vault = await createVault();
    const api = vault.as(vault.device.token);
    expect((await api.post("records", { records: [{ key: "a", base: "", blob: blob(2) }] })).body).toEqual({ error: "epoch" });
    expect((await api.post("records", { records: [{ key: "a", base: "", blob: b64(new Uint8Array(10)) }] })).status).toBe(400);
    expect((await api.post("records", { records: [{ key: "a", base: "", blob: blob(1, (1 << 20) + 1) }] })).status).toBe(413);
  });

  test("history keeps the current plus 5 previous versions", async () => {
    const vault = await createVault();
    const api = vault.as(vault.device.token);
    let version = "";
    for (let i = 0; i < 8; i++) {
      version = (await api.post("records", { records: [{ key: "h", base: version, blob: blob(1) }] })).body.versions.h;
    }
    const { body } = await api.get("records/h/history");
    expect(body.versions).toHaveLength(6);
    expect(body.versions[0].version).toBe(version);
  });

  test("changes are paginated", async () => {
    const vault = await createVault();
    const api = vault.as(vault.device.token);
    const records = Array.from({ length: 501 }, (_, i) => ({ key: `k${i}`, base: "", blob: blob(1) }));
    expect((await api.post("records", { records })).status).toBe(200);
    const first = await api.get("changes?since=0");
    expect(first.body.records).toHaveLength(500);
    expect(first.body.more).toBe(true);
    const second = await api.get(`changes?since=${first.body.cursor}`);
    expect(second.body.records).toHaveLength(1);
    expect(second.body.more).toBe(false);
  });
});

describe("members and keys", () => {
  test("rotation requires the exact member set and the current epoch", async () => {
    const vault = await createVault();
    const api = vault.as(vault.device.token);
    const missing = await api.put("keyring", { fromEpoch: 1, epoch: 2, entries: { recovery: "r2" } });
    expect(missing.status).toBe(409);
    expect(missing.body.error).toBe("members");
    expect(missing.body.members.sort()).toEqual([vault.device.id, "recovery"].sort());

    const entries = { recovery: "r2", [vault.device.id]: "d2" };
    expect((await api.put("keyring", { fromEpoch: 2, epoch: 3, entries })).body).toEqual({ error: "epoch" });
    expect((await api.put("keyring", { fromEpoch: 1, epoch: 2, entries })).status).toBe(204);
    expect((await api.get("keyring")).body).toMatchObject({ epoch: 2, keychain: "d2" });
    // Old-epoch blobs are refused after rotation.
    expect((await api.post("records", { records: [{ key: "a", base: "", blob: blob(1) }] })).body).toEqual({ error: "epoch" });
    expect((await api.post("records", { records: [{ key: "a", base: "", blob: blob(2) }] })).status).toBe(200);
  });

  test("adding and revoking devices", async () => {
    const vault = await createVault();
    const api = vault.as(vault.device.token);
    expect((await api.post("members", { id: randomId(), kind: "device", tokenHash: "h", keychain: "k", epoch: 9 })).body).toEqual({ error: "epoch" });
    expect((await api.post("members", { id: vault.device.id, kind: "device", tokenHash: "h", keychain: "k", epoch: 1 })).body).toEqual({ error: "exists" });
    expect((await api.post("members", { id: "recovery", kind: "recovery", tokenHash: "h", keychain: "k", epoch: 1 })).status).toBe(400);

    const other = await addDevice(vault);
    expect((await vault.as(other.token).get("keyring")).body.memberId).toBe(other.id);
    expect((await api.del("members/recovery")).status).toBe(403);
    expect((await api.del(`members/${other.id}`)).status).toBe(204);
    expect((await vault.as(other.token).get("keyring")).status).toBe(401);
    expect((await api.del(`members/${other.id}`)).status).toBe(404);
  });
});

describe("pairing", () => {
  test("mailbox flow", async () => {
    const vault = await createVault();
    const api = vault.as(vault.device.token);
    const pairing = randomId();
    const secret = randomId();
    expect((await api.post("pairings", { id: pairing, authHash: await hash(secret) })).status).toBe(201);
    expect((await api.get(`pairings/${pairing}`)).body).toEqual({ request: null });

    expect((await vault.as("wrong").post(`pairings/${pairing}/join`, { request: "hi" })).status).toBe(401);
    expect((await vault.as(secret).post(`pairings/${randomId()}/join`, { request: "hi" })).status).toBe(404);
    expect((await vault.as(secret).post(`pairings/${pairing}/join`, { request: "hello" })).status).toBe(202);
    expect((await vault.as(secret).post(`pairings/${pairing}/join`, { request: "again" })).status).toBe(409);
    expect((await api.get(`pairings/${pairing}`)).body).toEqual({ request: "hello" });

    const device = { id: randomId(), token: randomId() };
    expect((await api.post("members", {
      id: device.id, kind: "device", tokenHash: await hash(device.token), keychain: "k", epoch: 1, pairing,
    })).status).toBe(201);
    expect((await api.get(`pairings/${pairing}`)).status).toBe(404);
  });
});

describe("realtime", () => {
  /** Connects and waits for the ping/pong handshake that confirms the subscription. */
  async function open(vault: Vault, token: string) {
    const ws = new WebSocket(`${base.replace(/^http/, "ws")}/v1/vaults/${vault.id}/ws?token=${token}`);
    const messages: string[] = [];
    let closeCode: number | undefined;
    ws.onmessage = (event) => messages.push(String(event.data));
    ws.onclose = (event) => (closeCode = event.code);
    const until = async (check: () => boolean) => {
      for (let i = 0; i < 100 && !check(); i++) await Bun.sleep(20);
      expect(check()).toBe(true);
    };
    await new Promise((resolve, reject) => {
      ws.onopen = resolve;
      ws.onerror = reject;
    });
    ws.send("ping");
    await until(() => messages.includes("pong"));
    return { ws, messages, until, closeCode: () => closeCode };
  }

  test("notifies about writes", async () => {
    const vault = await createVault();
    const socket = await open(vault, vault.device.token);
    const write = await vault.as(vault.device.token).post("records", { records: [{ key: "a", base: "", blob: blob(1) }] });
    await socket.until(() => socket.messages.some((m) => m.includes('"changed"')));
    const changed = JSON.parse(socket.messages.find((m) => m.includes('"changed"'))!);
    expect(changed).toEqual({ type: "changed", cursor: write.body.versions.a });
    socket.ws.close();
  });

  test("closes revoked members with 4001", async () => {
    const vault = await createVault();
    const other = await addDevice(vault);
    const socket = await open(vault, other.token);
    await vault.as(vault.device.token).del(`members/${other.id}`);
    await socket.until(() => socket.closeCode() === 4001);
  });

  test("rejects unauthenticated sockets", async () => {
    const vault = await createVault();
    const response = await fetch(`${base}/v1/vaults/${vault.id}/ws?token=wrong`, { headers: { Upgrade: "websocket" } });
    expect(response.status).toBe(401);
  });
});

test("CORS preflight", async () => {
  const response = await fetch(`${base}/v1/vaults/${randomId()}/records`, {
    method: "OPTIONS",
    headers: { Origin: "https://example.com", "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "authorization" },
  });
  expect(response.ok).toBe(true);
  expect(response.headers.get("access-control-allow-origin")).toBe("*");
});
