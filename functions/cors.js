const ALLOWED_HOSTS = new Set([
  "github.com",
  "api.github.com",
  "codeload.github.com",
  "raw.githubusercontent.com",
  "objects.githubusercontent.com",
  "release-assets.githubusercontent.com",
]);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "*",
  "Cross-Origin-Resource-Policy": "cross-origin",
};

function reject(status, message) {
  return new Response(message, { status, headers: CORS_HEADERS });
}

export async function onRequest(context) {
  const { request } = context;

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return reject(405, "Method not allowed");
  }

  const marker = request.url.indexOf("url=");
  if (marker === -1) {
    return reject(400, "Missing url parameter");
  }

  let target = request.url.slice(marker + 4);
  if (/%[0-9a-fA-F]{2}/.test(target)) {
    try {
      target = decodeURIComponent(target);
    } catch (_) {
      return reject(400, "Malformed url parameter");
    }
  }

  let targetUrl;
  try {
    targetUrl = new URL(target);
  } catch (_) {
    return reject(400, "Invalid url");
  }

  if (targetUrl.protocol !== "https:" || !ALLOWED_HOSTS.has(targetUrl.hostname)) {
    return reject(403, "Host not allowed");
  }

  let upstream;
  try {
    upstream = await fetch(targetUrl.toString(), {
      method: request.method,
      headers: {
        Accept: request.headers.get("Accept") || "*/*",
        "User-Agent": "ChameleonUltraGUI-CORS-Relay",
      },
      redirect: "follow",
    });
  } catch (_) {
    return reject(502, "Upstream fetch failed");
  }

  const headers = new Headers(CORS_HEADERS);
  for (const name of [
    "content-type",
    "content-length",
    "content-disposition",
    "etag",
    "last-modified",
    "cache-control",
  ]) {
    const value = upstream.headers.get(name);
    if (value) {
      headers.set(name, value);
    }
  }

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers,
  });
}
