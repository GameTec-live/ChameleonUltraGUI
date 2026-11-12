/** Protocol error: an HTTP status plus a `{"error": code, …}` body. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly body: { error: string } & Record<string, unknown>,
  ) {
    super(body.error);
  }
  static badRequest = () => new ApiError(400, { error: "bad_request" });
  static unauthorized = () => new ApiError(401, { error: "unauthorized" });
  static forbidden = () => new ApiError(403, { error: "forbidden" });
  static notFound = () => new ApiError(404, { error: "not_found" });
  static tooLarge = () => new ApiError(413, { error: "too_large" });
  static conflict = (error: string) => new ApiError(409, { error });
}

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

export async function parseJson<T = Record<string, unknown>>(request: Request): Promise<T> {
  try {
    const value: unknown = await request.json();
    if (typeof value !== "object" || value === null) throw ApiError.badRequest();
    return value as T;
  } catch {
    throw ApiError.badRequest();
  }
}

export const validId = (id: unknown): id is string => typeof id === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(id);

export function b64encode(bytes: Uint8Array): string {
  let binary = "";
  // Chunked to stay below the argument limit of String.fromCharCode.
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function b64decode(text: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) throw ApiError.badRequest();
  const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/"));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

/** `hash(x)` from the protocol: b64url(SHA-256(utf8(x))). */
export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return b64encode(new Uint8Array(digest));
}
