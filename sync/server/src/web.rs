//! The web app at `/` (source in `../web`, embedded from its `dist` build).

use axum::http::{HeaderName, Uri, header};
use axum::response::{IntoResponse, Response};
use rust_embed::Embed;

use crate::error::ApiError;

#[derive(Embed)]
#[folder = "../web/dist"]
struct Assets;

/// Same as `../web/public/_headers`, which the Worker serves.
const HEADERS: [(HeaderName, &str); 3] = [
    (
        header::CONTENT_SECURITY_POLICY,
        "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; \
         base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    ),
    (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
    (header::REFERRER_POLICY, "no-referrer"),
];

pub async fn serve(uri: Uri) -> Response {
    let path = match uri.path().trim_start_matches('/') {
        "" => "index.html",
        path => path,
    };
    // `_headers` configures the Worker's asset hosting; HEADERS below is its equivalent.
    let Some(file) = Assets::get(path).filter(|_| path != "_headers") else {
        return ApiError::not_found().into_response();
    };
    // Bundles have content hashes in their names; everything else is revalidated.
    let cache = if path.starts_with("assets/") { "public, max-age=31536000, immutable" } else { "no-cache" };
    let mut response = (
        [(header::CONTENT_TYPE, file.metadata.mimetype()), (header::CACHE_CONTROL, cache)],
        file.data,
    )
        .into_response();
    for (name, value) in HEADERS {
        response.headers_mut().insert(name, value.parse().unwrap());
    }
    response
}
