//! In-process fan-out of realtime events to WebSocket connections per vault.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::broadcast;

#[derive(Clone, Debug)]
pub enum Event {
    /// A protocol message, forwarded verbatim to every socket of the vault.
    Message(String),
    /// Closes the sockets of this member with code 4001.
    Revoked(String),
}

#[derive(Default)]
pub struct Hub(Mutex<HashMap<String, broadcast::Sender<Event>>>);

impl Hub {
    pub fn subscribe(&self, vault: &str) -> broadcast::Receiver<Event> {
        let mut channels = self.0.lock().unwrap_or_else(|e| e.into_inner());
        channels
            .entry(vault.to_string())
            .or_insert_with(|| broadcast::channel(64).0)
            .subscribe()
    }

    pub fn publish(&self, vault: &str, event: Event) {
        let mut channels = self.0.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(sender) = channels.get(vault) {
            // Drop channels nobody listens to anymore.
            if sender.send(event).is_err() {
                channels.remove(vault);
            }
        }
    }
}
