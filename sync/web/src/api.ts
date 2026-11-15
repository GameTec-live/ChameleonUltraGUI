import { b64, unb64 } from "./crypto";

/** A protocol error: the server's `error` code and HTTP status. */
export class SyncError extends Error {
  constructor(
    readonly code: string,
    readonly status = 0,
  ) {
    super(code);
  }
}

export type RemoteRecord = { key: string; version: string; blob: Uint8Array };

type Info = { notice?: string };

/** HTTP client for one vault on the server this page came from (or [base]). */
export class Api {
  constructor(
    private readonly vaultId: string,
    private readonly token: string,
    private readonly base = "",
  ) {}

  static async info(base = ""): Promise<Info> {
    const response = await fetch(`${base}/v1/info`);
    return response.ok ? ((await response.json()) as Info) : {};
  }

  async call<T>(method: string, path: string, body?: unknown, token = this.token): Promise<T> {
    const response = await fetch(`${this.base}/v1/vaults/${this.vaultId}/${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    const json = text ? (JSON.parse(text) as T & { error?: string }) : null;
    if (!response.ok) throw new SyncError(json?.error ?? "http", response.status);
    return json as T;
  }

  keyring = () => this.call<{ epoch: number; keychain: string }>("GET", "keyring");

  async changes(since: string) {
    const page = await this.call<{ records: { key: string; version: string; blob: string }[]; cursor: string; more: boolean }>(
      "GET",
      `changes?since=${encodeURIComponent(since)}`,
    );
    return { ...page, records: page.records.map((r): RemoteRecord => ({ ...r, blob: unb64(r.blob) })) };
  }

  /** Compare-and-swap write; `base` is the version the change was made on ("" for new records). */
  async push(records: { key: string; base: string; blob: Uint8Array }[]) {
    const body = { records: records.map((r) => ({ ...r, blob: b64(r.blob) })) };
    return (await this.call<{ versions: Record<string, string> }>("POST", "records", body)).versions;
  }

  join = (pairing: string, authToken: string, request: string) =>
    this.call<null>("POST", `pairings/${pairing}/join`, { request }, authToken);

  revoke = (memberId: string) => this.call<null>("DELETE", `members/${memberId}`);
}
