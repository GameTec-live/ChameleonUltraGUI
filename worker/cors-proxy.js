// This is the prox used to proxy download request for the Chameleon Ultra GUI
// It is hosted on Cloudflare Workers and available under cors.gametec-live.com

const allowedOriginDomains = [
  'https://chameleon.run', // Allow production site
  /localhost:\d+/, // Allow development
]

// Check is done with 'startsWith'
const allowedUrlsToProxy = [
  'https://github.com/'
]

function getCorsHeaders(request) {
  const origin = request.headers.get('origin') || '';

  const isAllowed = allowedOriginDomains.some((allowedDomain) => {
    if (typeof allowedDomain === 'string') {
      return origin === allowedDomain
    }

    if (allowedDomain instanceof RegExp) {
      return origin.match(allowedDomain);
    }

    return false
  })

  return {
    'Access-Control-Allow-Origin': isAllowed ? origin : allowedOriginDomains[0],
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Allow-Methods': 'GET',
    'Access-Control-Allow-Headers': 'Origin, X-Requested-With, Content-Type, Accept, Authorization',
  }
}

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  try {
    const url = new URL(request.url);

    const upstreamUrl = request.url.slice(url.origin.length + 1);
    const isAllowedToProxy = allowedUrlsToProxy.some((url) => {
      return upstreamUrl.startsWith(url)
    })

    const corsHeaders = getCorsHeaders(request);

    if (!isAllowedToProxy) {
      const response = new Response('Forbidden', { status: 403, headers: corsHeaders })
      return response;
    }

    if (request.method == 'OPTIONS') {
      const response = new Response(null, { status: 204, headers: corsHeaders })
      return response;
    }

    const upstream = await fetch(upstreamUrl, {
        method: request.method,
        headers: request.headers,
        redirect: 'follow',
        body: request.body
    });

    const response = new Response(upstream.body, upstream)

    for (const [key, value] of Object.entries(corsHeaders)) {
      response.headers.set(key, value)
    }

    return response;
  } catch (e) {
    return new Response(e.stack || e, {status: 500});
  }
}