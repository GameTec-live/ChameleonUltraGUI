//! Per-client rate limits and who may create vaults.

use std::collections::HashMap;
use std::net::{IpAddr, Ipv6Addr};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use axum::http::HeaderMap;

/// What a limit counts.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Scope {
    /// Every request (WebSocket upgrades included).
    Request,
    /// Vault creation attempts.
    Signup,
}

impl Scope {
    /// Burst size and the time one request takes to earn back.
    fn rate(self) -> (u32, Duration) {
        match self {
            Scope::Request => (300, Duration::from_millis(200)), // 300 per minute
            Scope::Signup => (5, Duration::from_secs(12 * 60)), // 5 per hour
        }
    }
}

/// Token buckets per client, stored as GCRA "theoretical arrival times":
/// a client is limited while its time runs ahead of now by more than a burst.
pub struct Limiter {
    /// Multiplies every limit; `None` turns limiting off.
    scale: Option<u32>,
    state: Mutex<State>,
}

struct State {
    buckets: HashMap<(Scope, IpAddr), Instant>,
    next_prune: Instant,
}

impl Limiter {
    pub fn new(scale: Option<u32>) -> Self {
        let state = State { buckets: HashMap::new(), next_prune: Instant::now() };
        Self { scale, state: Mutex::new(state) }
    }

    /// Counts one `scope` request from `client`. When over the limit, returns
    /// the seconds until the next one is allowed.
    pub fn check(&self, scope: Scope, client: IpAddr) -> Result<(), u64> {
        let Some(scale) = self.scale else { return Ok(()) };
        let (burst, period) = scope.rate();
        let interval = period / scale;
        let tolerance = interval * (burst * scale - 1);
        let now = Instant::now();
        let mut state = self.state.lock().unwrap();
        if now >= state.next_prune {
            // A bucket whose time has passed is full again: same as no entry.
            state.buckets.retain(|_, at| *at > now);
            state.next_prune = now + Duration::from_secs(60);
        }
        let at = state.buckets.get(&(scope, client)).map_or(now, |at| (*at).max(now));
        if let Some(wait) = (at - now).checked_sub(tolerance).filter(|w| !w.is_zero()) {
            return Err(wait.as_secs_f64().ceil() as u64);
        }
        state.buckets.insert((scope, client), at + interval);
        Ok(())
    }
}

/// Where the client address comes from (`CU_SYNC_PROXY`).
#[derive(Clone, Copy)]
pub enum Proxy {
    /// Clients connect directly: the peer address.
    None,
    /// Behind one reverse proxy that appends to `X-Forwarded-For`.
    Forwarded,
    /// Behind Cloudflare (proxied DNS or a tunnel): `CF-Connecting-IP`.
    Cloudflare,
}

impl Proxy {
    /// The address limits apply to. IPv6 clients count per /64, since one
    /// host usually has a whole /64 to pick addresses from.
    pub fn client(self, peer: IpAddr, headers: &HeaderMap) -> IpAddr {
        let header = match self {
            Proxy::None => None,
            // The last entry is the one our proxy added; earlier ones are client-supplied.
            Proxy::Forwarded => headers.get_all("x-forwarded-for").iter().next_back(),
            Proxy::Cloudflare => headers.get("cf-connecting-ip"),
        };
        let ip = header
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.rsplit(',').next())
            .and_then(|v| v.trim().parse().ok())
            .unwrap_or(peer);
        match ip {
            IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
                Some(v4) => IpAddr::V4(v4),
                None => {
                    let [a, b, c, d, ..] = v6.segments();
                    IpAddr::V6(Ipv6Addr::new(a, b, c, d, 0, 0, 0, 0))
                }
            },
            v4 => v4,
        }
    }
}

/// Who may create vaults (`CU_SYNC_SIGNUP`, `CU_SYNC_SIGNUP_TOKEN`).
pub enum Signup {
    Open,
    /// Needs the token whose `hash_token` this is.
    Token(String),
    Closed,
}

impl Signup {
    /// How `GET /v1/info` describes it; `None` when open.
    pub fn describe(&self) -> Option<&'static str> {
        match self {
            Signup::Open => None,
            Signup::Token(_) => Some("token"),
            Signup::Closed => Some("closed"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CLIENT: IpAddr = IpAddr::V4(std::net::Ipv4Addr::new(192, 0, 2, 1));

    fn allowed(limiter: &Limiter, scope: Scope) -> usize {
        (0..100).take_while(|_| limiter.check(scope, CLIENT).is_ok()).count()
    }

    #[test]
    fn allows_a_burst_then_says_when_to_retry() {
        let limiter = Limiter::new(Some(1));
        assert_eq!(allowed(&limiter, Scope::Signup), 5);
        assert_eq!(limiter.check(Scope::Signup, CLIENT), Err(12 * 60));
        // Other clients and scopes are counted separately.
        assert!(limiter.check(Scope::Request, CLIENT).is_ok());
        assert!(limiter.check(Scope::Signup, "192.0.2.2".parse().unwrap()).is_ok());
    }

    #[test]
    fn scale_doubles_or_disables() {
        assert_eq!(allowed(&Limiter::new(Some(2)), Scope::Signup), 10);
        assert_eq!(allowed(&Limiter::new(None), Scope::Signup), 100);
    }

    #[test]
    fn client_address_follows_the_proxy_setting() {
        let peer: IpAddr = "10.0.0.1".parse().unwrap();
        let mut headers = HeaderMap::new();
        headers.insert("x-forwarded-for", "198.51.100.7, 203.0.113.9".parse().unwrap());
        headers.insert("cf-connecting-ip", "2001:db8:1:2:3:4:5:6".parse().unwrap());
        assert_eq!(Proxy::None.client(peer, &headers), peer);
        assert_eq!(Proxy::Forwarded.client(peer, &headers), "203.0.113.9".parse::<IpAddr>().unwrap());
        assert_eq!(Proxy::Cloudflare.client(peer, &headers), "2001:db8:1:2::".parse::<IpAddr>().unwrap());
        assert_eq!(Proxy::Cloudflare.client(peer, &HeaderMap::new()), peer);
    }
}
