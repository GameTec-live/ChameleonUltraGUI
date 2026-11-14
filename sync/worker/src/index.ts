import { type Env } from "./vault";
import { json, validId } from "./util";

export { Vault } from "./vault";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

/** Answers `/v1/info`, routes `/v1/vaults/{vaultId}/…` to that vault's Durable Object and adds CORS. */
export default {
  async fetch(request, env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const { pathname } = new URL(request.url);
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

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(CORS)) headers.set(name, value);
  return new Response(response.body, { status: response.status, headers });
}
