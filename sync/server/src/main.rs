//! Self-hostable Chameleon Ultra GUI sync server. Speaks the protocol in
//! `../PROTOCOL.md`; stores only ciphertext in a single SQLite file. Serves the
//! web app from `../web` (build it first: `bun run build` there).
//!
//! Configuration (environment variables):
//! - `CU_SYNC_BIND` (default `0.0.0.0:8787`)
//! - `CU_SYNC_DB` (default `sync.db`)
//! - `CU_SYNC_MAX_VAULT_BYTES` (default 64 MiB)
//! - `CU_SYNC_NOTICE` (optional): shown in the app before setup, e.g. who runs
//!   the server
//! - `CU_SYNC_RATE_LIMIT`: `on` (default: 300 requests per minute and 5 new
//!   vaults per hour per client), `double` or `off`
//! - `CU_SYNC_PROXY`: where the client address comes from: `none` (default,
//!   the connection), `forwarded` (last `X-Forwarded-For` entry, behind one
//!   reverse proxy) or `cloudflare` (`CF-Connecting-IP`, proxied DNS or a
//!   tunnel). Only set it when every request passes that proxy: clients can
//!   forge the header otherwise.
//! - `CU_SYNC_SIGNUP_TOKEN` (optional): creating a vault needs this token
//! - `CU_SYNC_SIGNUP`: `open` (default) or `closed` (no new vaults at all)

mod api;
mod error;
mod hub;
mod limit;
mod store;
mod web;

use std::net::SocketAddr;
use std::sync::Arc;

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use sha2::{Digest, Sha256};

pub struct Limits {
    pub blob_bytes: usize,
    pub vault_bytes: i64,
    pub history: i64,
    pub page_records: i64,
    pub page_bytes: usize,
    pub pairing_seconds: i64,
}

/// `hash(x)` from the protocol: b64url(SHA-256(utf8(x))).
pub fn hash_token(token: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(token.as_bytes()))
}

fn env_or<T: std::str::FromStr>(name: &str, default: T) -> T {
    std::env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

/// Reads a variable that must be one of `choices` (the first is the default).
/// Typos stop the server instead of silently loosening a restriction.
fn env_choice(name: &str, choices: &[&'static str]) -> &'static str {
    let Ok(value) = std::env::var(name) else { return choices[0] };
    let value = value.trim().to_ascii_lowercase();
    let choice = choices.iter().find(|c| **c == value);
    *choice.unwrap_or_else(|| panic!("{name} must be one of: {}", choices.join(", ")))
}

#[tokio::main]
async fn main() {
    let bind: String = env_or("CU_SYNC_BIND", "0.0.0.0:8787".to_string());
    let db: String = env_or("CU_SYNC_DB", "sync.db".to_string());
    let limits = Limits {
        blob_bytes: 1 << 20,
        vault_bytes: env_or("CU_SYNC_MAX_VAULT_BYTES", 64 << 20),
        history: 5,
        page_records: 500,
        page_bytes: 8 << 20,
        pairing_seconds: 600,
    };

    let store = store::Store::open(&db, limits).expect("failed to open database");
    let notice = std::env::var("CU_SYNC_NOTICE").ok().filter(|n| !n.trim().is_empty());
    let limiter = limit::Limiter::new(match env_choice("CU_SYNC_RATE_LIMIT", &["on", "double", "off"]) {
        "on" => Some(1),
        "double" => Some(2),
        _ => None,
    });
    let proxy = match env_choice("CU_SYNC_PROXY", &["none", "forwarded", "cloudflare"]) {
        "none" => limit::Proxy::None,
        "forwarded" => limit::Proxy::Forwarded,
        _ => limit::Proxy::Cloudflare,
    };
    let token = std::env::var("CU_SYNC_SIGNUP_TOKEN").ok().filter(|t| !t.trim().is_empty());
    let signup = match (env_choice("CU_SYNC_SIGNUP", &["open", "closed"]), token) {
        ("closed", _) => limit::Signup::Closed,
        (_, Some(token)) => limit::Signup::Token(hash_token(token.trim())),
        _ => limit::Signup::Open,
    };
    let state = Arc::new(api::AppState { store, hub: hub::Hub::default(), notice, limiter, proxy, signup });
    let listener = tokio::net::TcpListener::bind(&bind).await.expect("failed to bind");
    eprintln!("cu-sync-server listening on {bind}, database {db}");
    let app = api::router(state).into_make_service_with_connect_info::<SocketAddr>();
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await
        .expect("server error");
}
