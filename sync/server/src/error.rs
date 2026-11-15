use axum::Json;
use axum::http::StatusCode;
use axum::http::header::RETRY_AFTER;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

/// Protocol error: an HTTP status plus a `{"error": code, …}` body, and for
/// 429 the seconds until the client may retry.
#[derive(Debug)]
pub struct ApiError(StatusCode, Value, Option<u64>);

impl ApiError {
    fn code(status: StatusCode, code: &str) -> Self {
        Self(status, json!({ "error": code }), None)
    }
    pub fn bad_request() -> Self {
        Self::code(StatusCode::BAD_REQUEST, "bad_request")
    }
    pub fn unauthorized() -> Self {
        Self::code(StatusCode::UNAUTHORIZED, "unauthorized")
    }
    pub fn forbidden() -> Self {
        Self::code(StatusCode::FORBIDDEN, "forbidden")
    }
    /// Vault creation refused: `signup_closed` or `signup_token`.
    pub fn signup(code: &str) -> Self {
        Self::code(StatusCode::FORBIDDEN, code)
    }
    pub fn rate_limited(retry_after: u64) -> Self {
        Self(StatusCode::TOO_MANY_REQUESTS, json!({ "error": "rate_limited" }), Some(retry_after))
    }
    pub fn not_found() -> Self {
        Self::code(StatusCode::NOT_FOUND, "not_found")
    }
    pub fn conflict(code: &str) -> Self {
        Self::code(StatusCode::CONFLICT, code)
    }
    pub fn conflicts(keys: &[String]) -> Self {
        Self(StatusCode::CONFLICT, json!({ "error": "conflict", "keys": keys }), None)
    }
    pub fn members(ids: &[String]) -> Self {
        Self(StatusCode::CONFLICT, json!({ "error": "members", "members": ids }), None)
    }
    pub fn too_large() -> Self {
        Self::code(StatusCode::PAYLOAD_TOO_LARGE, "too_large")
    }
    pub fn quota() -> Self {
        Self::code(StatusCode::INSUFFICIENT_STORAGE, "quota")
    }
}

impl From<rusqlite::Error> for ApiError {
    fn from(error: rusqlite::Error) -> Self {
        match error {
            rusqlite::Error::QueryReturnedNoRows => Self::not_found(),
            error => {
                eprintln!("database error: {error}");
                Self::code(StatusCode::INTERNAL_SERVER_ERROR, "internal")
            }
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let mut response = (self.0, Json(self.1)).into_response();
        if let Some(seconds) = self.2 {
            response.headers_mut().insert(RETRY_AFTER, seconds.into());
        }
        response
    }
}
