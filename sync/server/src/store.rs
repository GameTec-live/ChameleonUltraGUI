//! SQLite persistence. Every public method is one transaction and maps
//! protocol violations to `ApiError`s, so handlers stay thin.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension, Transaction, params};

use crate::error::ApiError;
use crate::{Limits, hash_token};

pub struct Store {
    conn: Mutex<Connection>,
    pub limits: Limits,
}

pub struct Member {
    pub id: String,
    pub kind: String,
}

pub struct NewMember {
    pub id: String,
    pub kind: String,
    pub token_hash: String,
    pub keychain: String,
}

pub struct Record {
    pub key: String,
    pub version: i64,
    pub blob: Vec<u8>,
}

pub struct Changes {
    pub records: Vec<Record>,
    pub cursor: i64,
    pub more: bool,
}

const SCHEMA: &str = "
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS vaults (id TEXT PRIMARY KEY, epoch INTEGER NOT NULL, seq INTEGER NOT NULL, bytes INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS members (vault TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL, token_hash TEXT NOT NULL, keychain TEXT NOT NULL, PRIMARY KEY (vault, id));
CREATE INDEX IF NOT EXISTS members_token ON members (vault, token_hash);
CREATE TABLE IF NOT EXISTS records (vault TEXT NOT NULL, key TEXT NOT NULL, seq INTEGER NOT NULL, blob BLOB NOT NULL, PRIMARY KEY (vault, key));
CREATE INDEX IF NOT EXISTS records_seq ON records (vault, seq);
CREATE TABLE IF NOT EXISTS history (vault TEXT NOT NULL, key TEXT NOT NULL, seq INTEGER NOT NULL, blob BLOB NOT NULL, PRIMARY KEY (vault, key, seq));
CREATE TABLE IF NOT EXISTS pairings (vault TEXT NOT NULL, id TEXT NOT NULL, auth_hash TEXT NOT NULL, request TEXT, expires INTEGER NOT NULL, PRIMARY KEY (vault, id));
";

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// Reads the epoch from a record blob header: `[0x01][u32 BE epoch]…`.
fn blob_epoch(blob: &[u8]) -> Option<u32> {
    // Header (5) + nonce (24) + Poly1305 tag (16) is the smallest valid blob.
    if blob.len() < 45 || blob[0] != 1 {
        return None;
    }
    Some(u32::from_be_bytes(blob[1..5].try_into().ok()?))
}

impl Store {
    pub fn open(path: &str, limits: Limits) -> rusqlite::Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self {
            conn: Mutex::new(conn),
            limits,
        })
    }

    /// Runs `f` in an immediate transaction; commits only on `Ok`.
    fn tx<T>(&self, f: impl FnOnce(&Transaction) -> Result<T, ApiError>) -> Result<T, ApiError> {
        let mut conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
        let value = f(&tx)?;
        tx.commit()?;
        Ok(value)
    }

    pub fn init(&self, vault: &str, epoch: u32, members: &[NewMember]) -> Result<(), ApiError> {
        self.tx(|tx| {
            let exists: bool = tx
                .query_row("SELECT 1 FROM vaults WHERE id = ?", [vault], |_| Ok(true))
                .optional()?
                .is_some();
            if exists {
                return Err(ApiError::conflict("exists"));
            }
            tx.execute(
                "INSERT INTO vaults (id, epoch, seq, bytes) VALUES (?, ?, 0, 0)",
                params![vault, epoch],
            )?;
            for m in members {
                insert_member(tx, vault, m)?;
            }
            Ok(())
        })
    }

    /// Resolves a bearer token to a member, or 401.
    pub fn authenticate(&self, vault: &str, token: &str) -> Result<Member, ApiError> {
        self.tx(|tx| {
            tx.query_row(
                "SELECT id, kind FROM members WHERE vault = ? AND token_hash = ?",
                params![vault, hash_token(token)],
                |row| Ok(Member { id: row.get(0)?, kind: row.get(1)? }),
            )
            .optional()?
            .ok_or_else(ApiError::unauthorized)
        })
    }

    pub fn keyring(&self, vault: &str, member: &str) -> Result<(u32, String), ApiError> {
        self.tx(|tx| {
            Ok(tx.query_row(
                "SELECT v.epoch, m.keychain FROM vaults v JOIN members m ON m.vault = v.id WHERE v.id = ? AND m.id = ?",
                params![vault, member],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )?)
        })
    }

    pub fn members(&self, vault: &str) -> Result<(u32, Vec<Member>), ApiError> {
        self.tx(|tx| Ok((epoch(tx, vault)?, members(tx, vault)?)))
    }

    pub fn rotate(
        &self,
        vault: &str,
        from: u32,
        to: u32,
        entries: &HashMap<String, String>,
    ) -> Result<(), ApiError> {
        self.tx(|tx| {
            if epoch(tx, vault)? != from || to <= from {
                return Err(ApiError::conflict("epoch"));
            }
            let ids: Vec<String> = members(tx, vault)?.into_iter().map(|m| m.id).collect();
            let expected: HashSet<&String> = ids.iter().collect();
            if expected != entries.keys().collect() {
                return Err(ApiError::members(&ids));
            }
            for (id, keychain) in entries {
                tx.execute(
                    "UPDATE members SET keychain = ? WHERE vault = ? AND id = ?",
                    params![keychain, vault, id],
                )?;
            }
            tx.execute("UPDATE vaults SET epoch = ? WHERE id = ?", params![to, vault])?;
            Ok(())
        })
    }

    pub fn add_member(
        &self,
        vault: &str,
        member: &NewMember,
        member_epoch: u32,
        pairing: Option<&str>,
    ) -> Result<(), ApiError> {
        self.tx(|tx| {
            if epoch(tx, vault)? != member_epoch {
                return Err(ApiError::conflict("epoch"));
            }
            insert_member(tx, vault, member)?;
            if let Some(pairing) = pairing {
                tx.execute(
                    "DELETE FROM pairings WHERE vault = ? AND id = ?",
                    params![vault, pairing],
                )?;
            }
            Ok(())
        })
    }

    pub fn revoke(&self, vault: &str, id: &str) -> Result<(), ApiError> {
        if id == "recovery" {
            return Err(ApiError::forbidden());
        }
        self.tx(|tx| {
            let deleted = tx.execute(
                "DELETE FROM members WHERE vault = ? AND id = ?",
                params![vault, id],
            )?;
            if deleted == 0 {
                return Err(ApiError::not_found());
            }
            Ok(())
        })
    }

    pub fn changes(&self, vault: &str, since: i64) -> Result<Changes, ApiError> {
        self.tx(|tx| {
            let mut statement = tx.prepare(
                "SELECT key, seq, blob FROM records WHERE vault = ? AND seq > ? ORDER BY seq LIMIT ?",
            )?;
            let mut rows = statement.query(params![vault, since, self.limits.page_records + 1])?;
            let mut records = Vec::new();
            let mut bytes = 0;
            let mut more = false;
            while let Some(row) = rows.next()? {
                let blob: Vec<u8> = row.get(2)?;
                // Always return at least one record so a cursor can never stall.
                if records.len() as i64 == self.limits.page_records
                    || (!records.is_empty() && bytes + blob.len() > self.limits.page_bytes)
                {
                    more = true;
                    break;
                }
                bytes += blob.len();
                records.push(Record { key: row.get(0)?, version: row.get(1)?, blob });
            }
            let cursor = records.last().map_or(since, |r| r.version);
            Ok(Changes { records, cursor, more })
        })
    }

    /// Atomic compare-and-swap write of a batch. Returns the new versions.
    pub fn write(
        &self,
        vault: &str,
        records: &[(String, String, Vec<u8>)],
    ) -> Result<(HashMap<String, i64>, i64), ApiError> {
        if records.iter().any(|(_, _, blob)| blob.len() > self.limits.blob_bytes) {
            return Err(ApiError::too_large());
        }
        self.tx(|tx| {
            let (current_epoch, mut seq, mut bytes): (u32, i64, i64) = tx.query_row(
                "SELECT epoch, seq, bytes FROM vaults WHERE id = ?",
                [vault],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )?;
            let mut conflicts = Vec::new();
            for (key, base, blob) in records {
                match blob_epoch(blob) {
                    None => return Err(ApiError::bad_request()),
                    Some(e) if e != current_epoch => return Err(ApiError::conflict("epoch")),
                    _ => {}
                }
                let current: Option<i64> = tx
                    .query_row(
                        "SELECT seq FROM records WHERE vault = ? AND key = ?",
                        params![vault, key],
                        |row| row.get(0),
                    )
                    .optional()?;
                if current.map_or(String::new(), |v| v.to_string()) != *base {
                    conflicts.push(key.clone());
                }
            }
            if !conflicts.is_empty() {
                return Err(ApiError::conflicts(&conflicts));
            }

            let mut versions = HashMap::new();
            for (key, _, blob) in records {
                seq += 1;
                // Move the previous version into history, then prune it to the limit.
                tx.execute(
                    "INSERT INTO history (vault, key, seq, blob) SELECT vault, key, seq, blob FROM records WHERE vault = ? AND key = ?",
                    params![vault, key],
                )?;
                let pruned: i64 = tx.query_row(
                    "SELECT COALESCE(SUM(length(blob)), 0) FROM (SELECT blob FROM history WHERE vault = ?1 AND key = ?2 ORDER BY seq DESC LIMIT -1 OFFSET ?3)",
                    params![vault, key, self.limits.history],
                    |row| row.get(0),
                )?;
                tx.execute(
                    "DELETE FROM history WHERE vault = ?1 AND key = ?2 AND seq NOT IN (SELECT seq FROM history WHERE vault = ?1 AND key = ?2 ORDER BY seq DESC LIMIT ?3)",
                    params![vault, key, self.limits.history],
                )?;
                tx.execute(
                    "INSERT INTO records (vault, key, seq, blob) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (vault, key) DO UPDATE SET seq = ?3, blob = ?4",
                    params![vault, key, seq, blob],
                )?;
                bytes += blob.len() as i64 - pruned;
                versions.insert(key.clone(), seq);
            }
            if bytes > self.limits.vault_bytes {
                return Err(ApiError::quota());
            }
            tx.execute(
                "UPDATE vaults SET seq = ?, bytes = ? WHERE id = ?",
                params![seq, bytes, vault],
            )?;
            Ok((versions, seq))
        })
    }

    pub fn history(&self, vault: &str, key: &str) -> Result<Vec<Record>, ApiError> {
        self.tx(|tx| {
            let mut statement = tx.prepare(
                "SELECT key, seq, blob FROM records WHERE vault = ?1 AND key = ?2
                 UNION ALL SELECT key, seq, blob FROM history WHERE vault = ?1 AND key = ?2
                 ORDER BY seq DESC",
            )?;
            let rows = statement.query_map(params![vault, key], |row| {
                Ok(Record { key: row.get(0)?, version: row.get(1)?, blob: row.get(2)? })
            })?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    pub fn open_pairing(&self, vault: &str, id: &str, auth_hash: &str) -> Result<(), ApiError> {
        self.tx(|tx| {
            tx.execute("DELETE FROM pairings WHERE expires < ?", [now()])?;
            let inserted = tx.execute(
                "INSERT OR IGNORE INTO pairings (vault, id, auth_hash, expires) VALUES (?, ?, ?, ?)",
                params![vault, id, auth_hash, now() + self.limits.pairing_seconds],
            )?;
            if inserted == 0 {
                return Err(ApiError::conflict("exists"));
            }
            Ok(())
        })
    }

    pub fn join_pairing(&self, vault: &str, id: &str, token: &str, request: &str) -> Result<(), ApiError> {
        self.tx(|tx| {
            let pairing: Option<(String, Option<String>)> = tx
                .query_row(
                    "SELECT auth_hash, request FROM pairings WHERE vault = ? AND id = ? AND expires >= ?",
                    params![vault, id, now()],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .optional()?;
            match pairing {
                None => Err(ApiError::not_found()),
                Some((auth, _)) if auth != hash_token(token) => Err(ApiError::unauthorized()),
                Some((_, Some(_))) => Err(ApiError::conflict("exists")),
                Some(_) => {
                    tx.execute(
                        "UPDATE pairings SET request = ? WHERE vault = ? AND id = ?",
                        params![request, vault, id],
                    )?;
                    Ok(())
                }
            }
        })
    }

    pub fn pairing(&self, vault: &str, id: &str) -> Result<Option<String>, ApiError> {
        self.tx(|tx| {
            tx.query_row(
                "SELECT request FROM pairings WHERE vault = ? AND id = ? AND expires >= ?",
                params![vault, id, now()],
                |row| row.get(0),
            )
            .optional()?
            .ok_or_else(ApiError::not_found)
        })
    }
}

fn epoch(tx: &Transaction, vault: &str) -> Result<u32, ApiError> {
    Ok(tx.query_row("SELECT epoch FROM vaults WHERE id = ?", [vault], |row| row.get(0))?)
}

fn members(tx: &Transaction, vault: &str) -> Result<Vec<Member>, ApiError> {
    let mut statement = tx.prepare("SELECT id, kind FROM members WHERE vault = ? ORDER BY id")?;
    let rows = statement.query_map([vault], |row| Ok(Member { id: row.get(0)?, kind: row.get(1)? }))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
}

fn insert_member(tx: &Transaction, vault: &str, m: &NewMember) -> Result<(), ApiError> {
    let inserted = tx.execute(
        "INSERT OR IGNORE INTO members (vault, id, kind, token_hash, keychain) VALUES (?, ?, ?, ?, ?)",
        params![vault, m.id, m.kind, m.token_hash, m.keychain],
    )?;
    if inserted == 0 {
        return Err(ApiError::conflict("exists"));
    }
    Ok(())
}
