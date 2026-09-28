# Plex Networking & Connection Management

## 1. Goals

- Discover all servers the signed-in account can access
- Rank and probe connection candidates
- Maintain a stable “active connection” for API + playback
- React to network path changes without unnecessary playback disruption
- Prefer the highest quality path (local direct > remote direct > relay)

## 2. Discovery Sources

### 2.1 Account Resources (primary)

```
GET https://plex.tv/api/v2/resources
  ?includeHttps=1
  &includeRelay=1
  &includeIPv6=1
```

Requires plex.tv token. Returns devices; filter those with `provides` containing `server`.

Each server resource yields:

- Identity (`clientIdentifier` / machine id, name, product version, platform)
- `accessToken` scoped to that server
- `connections[]` array

### 2.2 Connection Object Fields

| Field | Meaning |
|-------|---------|
| `uri` | Full base URL to try |
| `address` / `port` | Host components |
| `protocol` | `http` / `https` |
| `local` | Likely same LAN |
| `relay` | Plex Relay path (bandwidth limited) |
| `IPv6` | IPv6 candidate |

### 2.3 Supplementary Discovery

- Local GDM / SSDP style discovery (optional enhancement; many modern clients rely primarily on plex.tv resources)
- Manual / custom server URL entry (Settings)
- Previously successful connection cache (persisted, encrypted if sensitive)

## 3. ConnectionManager Responsibilities

```
discover()           → list of PlexServer + candidates
resolveConnection()  → ordered candidate list for a server
testConnection()     → latency / identity / token validity probe
selectBestConnection()
refreshConnections() → on network change or manual refresh
activeConnection     → current base URL + token + quality class
```

### 3.1 Ranking Heuristic (default)

1. Local + HTTPS
2. Local + HTTP (only if server advertises / allows)
3. Remote direct HTTPS (publicAddressMatches or successful probe)
4. Custom published URLs
5. Relay

Within the same class, prefer lower latency and IPv4 vs IPv6 according to measured success.

### 3.2 Probe

Minimal probe:

```
GET {candidate}/identity
  or
GET {candidate}/
```

Validate:

- Reachability
- Matching `machineIdentifier` (prevents wrong server)
- Optional authenticated call (`/library/sections`) to confirm token

Timeouts should be short for ranking (e.g. 1–3 s) and longer for established sessions.

## 4. Network Path Monitoring

Use `Network.framework` / `NWPathMonitor`:

- Interface type: Wi-Fi, Cellular, Wired, Other
- Expensive / constrained flags
- Satisfied vs unsatisfied

### On path change

1. Re-rank candidates for the active server
2. If a clearly better local connection appears, consider seamless switch for **API** traffic
3. For **active playback**, prefer stability:
   - Do not tear down AVPlayer solely because a new candidate ranked higher
   - Only switch if current path becomes unusable
4. Update UI connection quality indicator

## 5. Relay Considerations

- Last-resort path when direct remote access fails (CGNAT, strict firewall, etc.)
- Hard bandwidth cap (~2 Mbps historically) → forces lower quality / more transcoding
- Downloads / high-bitrate Direct Play generally unsuitable over Relay
- Surface “Indirect / Relay” status to the user when relevant

## 6. Security & Transport

- Prefer HTTPS for non-local connections
- Local HTTP is acceptable when the server only offers it and the network is trusted
- Certificate handling: plex.direct hostnames use Plex-issued certs; standard URLSession trust evaluation usually works
- Never log full URLs containing tokens

## 7. Multi-Server Support

- User may own or be invited to multiple PMS instances
- UI should allow server switching
- Each server keeps its own:
  - access token
  - connection candidate set
  - cached metadata scope
- Active playback is always bound to one server context

## 8. Failure Modes & Recovery

| Failure | Recovery |
|---------|----------|
| All candidates fail | Show server offline; background retry with backoff |
| Token 401 | Invalidate auth; clear server tokens if account-level failure |
| Intermittent WAN | Sticky current connection; probe in background |
| Network offline | Freeze non-critical refresh; keep local caches readable |
| DNS rebinding / plex.direct issues | Fall back to IP-based candidates when available |

## 9. Implementation Notes (iOS)

- `ConnectionManager` as an `actor` or isolated class to serialize probes
- Parallel probes with `TaskGroup` + overall deadline
- Persist last-known-good connection (host, port, protocol, local flag) for faster cold start
- Expose `AsyncStream` or observation for connection state changes
- Integrate with `PlaybackEngine` via a narrow protocol (`ServerContextProviding`) so playback does not depend on full manager internals

## 10. Testing Scenarios

- Single LAN server
- Multiple servers, mixed local/remote
- Forced Relay only
- Wi-Fi → Cellular transition mid-browse and mid-playback
- Airplane mode → restore
- Invalid / revoked token
- Server renames / machineIdentifier change
- IPv6-only candidate
- Custom reverse-proxy URL
