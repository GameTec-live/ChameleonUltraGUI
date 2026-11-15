import { type Env } from "./vault";
import { json, validId } from "./util";

export { Vault } from "./vault";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

/**
 * Rate limits, answers `/v1/info`, routes `/v1/vaults/{vaultId}/…` to that
 * vault's Durable Object and adds CORS.
 */
export default {
  async fetch(request, env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const { pathname } = new URL(request.url);
    if (env.RATE_LIMIT !== "off") {
      const key = clientKey(request.headers.get("CF-Connecting-IP") ?? "");
      const signup = request.method === "POST" && pathname.endsWith("/init");
      const allowed =
        (await env.REQUESTS.limit({ key })).success && (!signup || (await env.SIGNUPS.limit({ key })).success);
      // The binding counts per fixed minute, so a minute always suffices.
      if (!allowed) return withCors(json({ error: "rate_limited" }, 429, { "Retry-After": "60" }));
    }
    if (request.method === "GET" && pathname === "/v1/info") {
      return withCors(json(env.NOTICE ? { notice: env.NOTICE } : {}));
    }
    const [, version, vaults, vault] = pathname.split("/");
    if (version !== "v1" || vaults !== "vaults" || !validId(vault)) {
      return withCors(json({ error: "not_found" }, 404));
    }
    const response = await env.VAULTS.get(env.VAULTS.idFromName(vault)).fetch(request);
    return response.webSocket ? response : withCors(response);
  },
} satisfies ExportedHandler<Env>;

/** Rate limit key: the IPv4 address, or the /64 of an IPv6 one (one host usually has all of it). */
function clientKey(ip: string): string {
  if (!ip.includes(":")) return ip;
  const [head = "", tail = ""] = ip.split("::");
  const left = head ? head.split(":") : [];
  const right = tail ? tail.split(":") : [];
  const groups = [...left, ...Array<string>(8 - left.length - right.length).fill("0"), ...right];
  return `${groups.slice(0, 4).join(":")}::/64`;
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(CORS)) headers.set(name, value);
  return new Response(response.body, { status: response.status, headers });
}
