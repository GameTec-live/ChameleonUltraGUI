//! HTTP + WebSocket handlers. See `../PROTOCOL.md` for the contract.

use std::collections::HashMap;
use std::sync::Arc;

use axum::Router;
use axum::body::Bytes;
use axum::extract::ws::rejection::WebSocketUpgradeRejection;
use axum::extract::ws::{CloseFrame, Message, WebSocket, WebSocketUpgrade};
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::Json;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use tokio::sync::broadcast::Receiver;
use tokio::sync::broadcast::error::RecvError;
use tower_http::cors::CorsLayer;

use crate::error::ApiError;
use crate::hub::{Event, Hub};
use crate::store::{Member, NewMember, Store};

pub struct AppState {
    pub store: Store,
    pub hub: Hub,
}

type AppResult<T> = Result<T, ApiError>;
type St = State<Arc<AppState>>;

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/v1/vaults/{vault}/init", post(init))
        .route("/v1/vaults/{vault}/keyring", get(keyring).put(rotate))
        .route("/v1/vaults/{vault}/members", get(members).post(add_member))
        .route("/v1/vaults/{vault}/members/{id}", delete(revoke))
        .route("/v1/vaults/{vault}/changes", get(changes))
        .route("/v1/vaults/{vault}/records", post(write))
        .route("/v1/vaults/{vault}/records/{key}/history", get(history))
        .route("/v1/vaults/{vault}/pairings", post(open_pairing))
        .route("/v1/vaults/{vault}/pairings/{id}", get(pairing))
        .route("/v1/vaults/{vault}/pairings/{id}/join", post(join_pairing))
        .route("/v1/vaults/{vault}/ws", get(socket))
        .layer(DefaultBodyLimit::max(16 << 20))
        .layer(CorsLayer::permissive())
        .with_state(state)
}

fn valid_id(id: &str) -> bool {
    (1..=64).contains(&id.len())
        && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// Validates every path/body identifier before it reaches the database.
fn ids<'a>(values: impl IntoIterator<Item = &'a str>) -> AppResult<()> {
    if values.into_iter().all(valid_id) { Ok(()) } else { Err(ApiError::bad_request()) }
}

fn parse<T: DeserializeOwned>(body: &Bytes) -> AppResult<T> {
    serde_json::from_slice(body).map_err(|_| ApiError::bad_request())
}

fn bearer(headers: &HeaderMap) -> AppResult<&str> {
    headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .ok_or_else(ApiError::unauthorized)
}

fn auth(state: &AppState, vault: &str, headers: &HeaderMap) -> AppResult<Member> {
    ids([vault])?;
    state.store.authenticate(vault, bearer(headers)?)
}

fn publish(state: &AppState, vault: &str, message: Value) {
    state.hub.publish(vault, Event::Message(message.to_string()));
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MemberBody {
    id: String,
    kind: String,
    token_hash: String,
    keychain: String,
    #[serde(default)]
    epoch: u32,
    pairing: Option<String>,
}

impl MemberBody {
    fn validate(self) -> AppResult<NewMember> {
        // The recovery member always has the id "recovery"; devices never do.
        let kind_ok = match self.kind.as_str() {
            "recovery" => self.id == "recovery",
            "device" => self.id != "recovery",
            _ => false,
        };
        ids([self.id.as_str(), self.token_hash.as_str()])?;
        if !kind_ok || self.keychain.is_empty() || self.keychain.len() > 8192 {
            return Err(ApiError::bad_request());
        }
        Ok(NewMember { id: self.id, kind: self.kind, token_hash: self.token_hash, keychain: self.keychain })
    }
}

#[derive(Deserialize)]
struct InitBody {
    epoch: u32,
    members: Vec<MemberBody>,
}

async fn init(State(s): St, Path(vault): Path<String>, body: Bytes) -> AppResult<StatusCode> {
    ids([vault.as_str()])?;
    let body: InitBody = parse(&body)?;
    let members = body.members.into_iter().map(MemberBody::validate).collect::<AppResult<Vec<_>>>()?;
    if members.iter().filter(|m| m.kind == "recovery").count() != 1 || body.epoch == 0 {
        return Err(ApiError::bad_request());
    }
    s.store.init(&vault, body.epoch, &members)?;
    Ok(StatusCode::CREATED)
}

async fn keyring(State(s): St, Path(vault): Path<String>, headers: HeaderMap) -> AppResult<Json<Value>> {
    let member = auth(&s, &vault, &headers)?;
    let (epoch, keychain) = s.store.keyring(&vault, &member.id)?;
    Ok(Json(json!({ "memberId": member.id, "kind": member.kind, "epoch": epoch, "keychain": keychain })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RotateBody {
    from_epoch: u32,
    epoch: u32,
    entries: HashMap<String, String>,
}

async fn rotate(State(s): St, Path(vault): Path<String>, headers: HeaderMap, body: Bytes) -> AppResult<StatusCode> {
    auth(&s, &vault, &headers)?;
    let body: RotateBody = parse(&body)?;
    ids(body.entries.keys().map(String::as_str))?;
    s.store.rotate(&vault, body.from_epoch, body.epoch, &body.entries)?;
    publish(&s, &vault, json!({ "type": "keyring", "epoch": body.epoch }));
    Ok(StatusCode::NO_CONTENT)
}

async fn members(State(s): St, Path(vault): Path<String>, headers: HeaderMap) -> AppResult<Json<Value>> {
    auth(&s, &vault, &headers)?;
    let (epoch, members) = s.store.members(&vault)?;
    let members: Vec<Value> = members.into_iter().map(|m| json!({ "id": m.id, "kind": m.kind })).collect();
    Ok(Json(json!({ "epoch": epoch, "members": members })))
}

async fn add_member(State(s): St, Path(vault): Path<String>, headers: HeaderMap, body: Bytes) -> AppResult<StatusCode> {
    auth(&s, &vault, &headers)?;
    let body: MemberBody = parse(&body)?;
    let (epoch, pairing) = (body.epoch, body.pairing.clone());
    if let Some(pairing) = &pairing {
        ids([pairing.as_str()])?;
    }
    let member = body.validate()?;
    if member.kind != "device" {
        return Err(ApiError::bad_request());
    }
    s.store.add_member(&vault, &member, epoch, pairing.as_deref())?;
    publish(&s, &vault, json!({ "type": "members" }));
    Ok(StatusCode::CREATED)
}

async fn revoke(State(s): St, Path((vault, id)): Path<(String, String)>, headers: HeaderMap) -> AppResult<StatusCode> {
    auth(&s, &vault, &headers)?;
    ids([id.as_str()])?;
    s.store.revoke(&vault, &id)?;
    s.hub.publish(&vault, Event::Revoked(id));
    publish(&s, &vault, json!({ "type": "members" }));
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
struct ChangesQuery {
    since: Option<String>,
}

async fn changes(
    State(s): St,
    Path(vault): Path<String>,
    Query(query): Query<ChangesQuery>,
    headers: HeaderMap,
) -> AppResult<Json<Value>> {
    auth(&s, &vault, &headers)?;
    let since: i64 = query.since.as_deref().unwrap_or("0").parse().map_err(|_| ApiError::bad_request())?;
    let changes = s.store.changes(&vault, since)?;
    let records: Vec<Value> = changes
        .records
        .into_iter()
        .map(|r| json!({ "key": r.key, "version": r.version.to_string(), "blob": URL_SAFE_NO_PAD.encode(r.blob) }))
        .collect();
    Ok(Json(json!({ "records": records, "cursor": changes.cursor.to_string(), "more": changes.more })))
}

#[derive(Deserialize)]
struct WriteRecord {
    key: String,
    base: String,
    blob: String,
}

#[derive(Deserialize)]
struct WriteBody {
    records: Vec<WriteRecord>,
}

async fn write(State(s): St, Path(vault): Path<String>, headers: HeaderMap, body: Bytes) -> AppResult<Json<Value>> {
    auth(&s, &vault, &headers)?;
    let body: WriteBody = parse(&body)?;
    let records = body
        .records
        .into_iter()
        .map(|r| {
            ids([r.key.as_str()])?;
            let blob = URL_SAFE_NO_PAD.decode(r.blob).map_err(|_| ApiError::bad_request())?;
            Ok((r.key, r.base, blob))
        })
        .collect::<AppResult<Vec<_>>>()?;
    if records.is_empty() {
        return Err(ApiError::bad_request());
    }
    let (versions, cursor) = s.store.write(&vault, &records)?;
    let versions: HashMap<String, String> = versions.into_iter().map(|(k, v)| (k, v.to_string())).collect();
    publish(&s, &vault, json!({ "type": "changed", "cursor": cursor.to_string() }));
    Ok(Json(json!({ "versions": versions })))
}

async fn history(State(s): St, Path((vault, key)): Path<(String, String)>, headers: HeaderMap) -> AppResult<Json<Value>> {
    auth(&s, &vault, &headers)?;
    ids([key.as_str()])?;
    let versions: Vec<Value> = s
        .store
        .history(&vault, &key)?
        .into_iter()
        .map(|r| json!({ "version": r.version.to_string(), "blob": URL_SAFE_NO_PAD.encode(r.blob) }))
        .collect();
    Ok(Json(json!({ "versions": versions })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenPairingBody {
    id: String,
    auth_hash: String,
}

async fn open_pairing(State(s): St, Path(vault): Path<String>, headers: HeaderMap, body: Bytes) -> AppResult<StatusCode> {
    auth(&s, &vault, &headers)?;
    let body: OpenPairingBody = parse(&body)?;
    ids([body.id.as_str(), body.auth_hash.as_str()])?;
    s.store.open_pairing(&vault, &body.id, &body.auth_hash)?;
    Ok(StatusCode::CREATED)
}

#[derive(Deserialize)]
struct JoinBody {
    request: String,
}

async fn join_pairing(
    State(s): St,
    Path((vault, id)): Path<(String, String)>,
    headers: HeaderMap,
    body: Bytes,
) -> AppResult<StatusCode> {
    ids([vault.as_str(), id.as_str()])?;
    let body: JoinBody = parse(&body)?;
    if body.request.len() > 4096 {
        return Err(ApiError::too_large());
    }
    s.store.join_pairing(&vault, &id, bearer(&headers)?, &body.request)?;
    publish(&s, &vault, json!({ "type": "pairing", "id": id }));
    Ok(StatusCode::ACCEPTED)
}

async fn pairing(State(s): St, Path((vault, id)): Path<(String, String)>, headers: HeaderMap) -> AppResult<Json<Value>> {
    auth(&s, &vault, &headers)?;
    ids([id.as_str()])?;
    Ok(Json(json!({ "request": s.store.pairing(&vault, &id)? })))
}

#[derive(Deserialize)]
struct SocketQuery {
    token: String,
}

async fn socket(
    State(s): St,
    Path(vault): Path<String>,
    Query(query): Query<SocketQuery>,
    upgrade: Result<WebSocketUpgrade, WebSocketUpgradeRejection>,
) -> Response {
    let member = match ids([vault.as_str()]).and_then(|_| s.store.authenticate(&vault, &query.token)) {
        Ok(member) => member,
        Err(error) => return error.into_response(),
    };
    let Ok(upgrade) = upgrade else {
        return ApiError::bad_request().into_response();
    };
    // Subscribe before upgrading so no event between handshake and first poll is lost.
    let events = s.hub.subscribe(&vault);
    upgrade.on_upgrade(move |ws| serve_socket(events, member.id, ws))
}

async fn serve_socket(mut events: Receiver<Event>, member: String, mut ws: WebSocket) {
    loop {
        tokio::select! {
            incoming = ws.recv() => match incoming {
                Some(Ok(Message::Text(text))) if text.as_str() == "ping" => {
                    if ws.send(Message::Text("pong".into())).await.is_err() { break; }
                }
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                Some(Ok(_)) => {}
            },
            event = events.recv() => match event {
                Ok(Event::Message(text)) => {
                    if ws.send(Message::Text(text.into())).await.is_err() { break; }
                }
                Ok(Event::Revoked(id)) if id == member => {
                    let frame = CloseFrame { code: 4001, reason: "revoked".into() };
                    let _ = ws.send(Message::Close(Some(frame))).await;
                    break;
                }
                Ok(Event::Revoked(_)) => {}
                // A slow client missed events; a "changed" nudge makes it pull everything it needs.
                Err(RecvError::Lagged(_)) => {
                    let nudge = json!({ "type": "changed" }).to_string();
                    if ws.send(Message::Text(nudge.into())).await.is_err() { break; }
                }
                Err(RecvError::Closed) => break,
            },
        }
    }
}
