//! Self-hostable Chameleon Ultra GUI sync server. Speaks the protocol in
//! `../PROTOCOL.md`; stores only ciphertext in a single SQLite file.
//!
//! Configuration (environment variables):
//! - `CU_SYNC_BIND` (default `0.0.0.0:8787`)
//! - `CU_SYNC_DB` (default `sync.db`)
//! - `CU_SYNC_MAX_VAULT_BYTES` (default 64 MiB)

mod api;
mod error;
mod hub;
mod store;

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
    let state = Arc::new(api::AppState { store, hub: hub::Hub::default() });
    let listener = tokio::net::TcpListener::bind(&bind).await.expect("failed to bind");
    eprintln!("cu-sync-server listening on {bind}, database {db}");
    axum::serve(listener, api::router(state))
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await
        .expect("server error");
}
