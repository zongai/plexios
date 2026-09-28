# Plex API Reference (Client Perspective)

This document summarizes the Plex protocol surfaces required by a native iOS client. Prefer official sources:

- https://developer.plex.tv/pms/
- Community OpenAPI (LukeHagar / plex-api-spec) for additional detail
- Behavioral study of mature clients (plex-for-kodi, python-plexapi, etc.)

Prefer **JSON** (`Accept: application/json`) for new code. XML remains the historical default.

## 1. Client Identification Headers

Include on essentially every request:

| Header | Purpose |
|--------|---------|
| `X-Plex-Client-Identifier` | Stable UUID for this app install |
| `X-Plex-Product` | e.g. `Plex iOS Native` |
| `X-Plex-Version` | App version |
| `X-Plex-Platform` | `iOS` |
| `X-Plex-Platform-Version` | iOS version |
| `X-Plex-Device` | Device model family |
| `X-Plex-Device-Name` | User-visible name |
| `X-Plex-Device-Vendor` | `Apple` |
| `X-Plex-Token` | Auth token (header preferred over query) |
| `X-Plex-Model` | Optional model identifier |

All `X-Plex-*` headers may also be sent as query parameters; prefer headers for tokens.

## 2. Authentication Surfaces

### 2.1 PIN Flow (Recommended for new clients)

1. `POST https://clients.plex.tv/api/v2/pins` (or `https://plex.tv/api/v2/pins`)
   - Headers: client identification
   - Body / params: `strong=true` (longer PIN lifetime)
   - Optional modern path: include device JWK for JWT issuance
2. Present `code` to user → open `https://plex.tv/link` or Auth App URL
3. Poll `GET .../pins/{id}` until `authToken` is non-null
4. Store token securely (Keychain)

### 2.2 JWT / Device Key Flow (2025+)

- Register Ed25519 (or RSA) JWK
- Exchange signed device JWT for short-lived (~7 day) Plex JWT
- Refresh via `POST https://clients.plex.tv/api/v2/auth/token`
- PMS currently accepts both legacy long-lived tokens and JWTs in `X-Plex-Token`

### 2.3 Token Usage

- **plex.tv token** — account operations, resource discovery
- **Server access token** — returned inside resource/device payloads; used against that PMS

Treat any token as a password. Never log it.

## 3. Server Discovery & Connection

### 3.1 Account Resources

```
GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1
```

Filter `provides` containing `server`. Each resource contains:

- `clientIdentifier` / `machineIdentifier`
- `accessToken` (server-scoped)
- `connections[]`:
  - `uri`, `address`, `port`, `protocol`
  - `local`, `relay`, `IPv6`

### 3.2 Connection Preference Order (typical)

1. Local HTTPS / HTTP (LAN)
2. Remote direct HTTPS
3. Custom published URLs
4. Relay (bandwidth-capped, last resort)

### 3.3 Identity Probe

```
GET {serverBase}/  or  /identity
```

Often works without token on LAN; returns `machineIdentifier`, version, claimed status.

## 4. Library & Metadata

### 4.1 Sections (Libraries)

```
GET /library/sections
```

Returns directories with `type` (movie=1, show=2, artist=8, …), `key`, `title`, `uuid`, etc.

### 4.2 Library Content

```
GET /library/sections/{id}/all
GET /library/sections/{id}/recentlyAdded
```

Pagination via headers:

- `X-Plex-Container-Start`
- `X-Plex-Container-Size`

Or query `limit`.

### 4.3 Hubs (Home)

```
GET /hubs
GET /hubs/home
GET /hubs/promoted
```

Hubs drive Continue Watching, Recently Added, recommendations, etc.

### 4.4 Single Metadata Item

```
GET /library/metadata/{ratingKey}
```

Useful includes (query params vary by PMS version):

- `includeMarkers=1`
- `includeChapters=1`
- `includeChildren=1` (shows / seasons)
- `includeRelated=1`
- `includeExtras=1`

### 4.5 Hierarchy

| Type | Children access |
|------|-----------------|
| Show | `/library/metadata/{showKey}/children` → seasons |
| Season | `/library/metadata/{seasonKey}/children` → episodes |
| Collection / Playlist | respective item endpoints |

### 4.6 Search

```
GET /hubs/search?query=...
GET /library/search?query=...
```

Client must debounce and cancel in-flight requests.

## 5. Media Hierarchy

```
Metadata (movie / episode / …)
  └── Media[]          (versions / qualities)
        └── Part[]     (files / segments)
              └── Stream[]  (video=1, audio=2, subtitle=3)
```

Key fields:

**Media**

- `container`, `videoCodec`, `audioCodec`, `videoResolution`, `bitrate`, `width`, `height`, `videoFrameRate`, `audioChannels`, `duration`, `videoProfile`, …

**Part**

- `key` (path to file or stream endpoint)
- `container`, `size`, `duration`, `file`, `indexes` (BIF), `accessible`

**Stream**

- `streamType`, `codec`, `language`, `languageCode`, `displayTitle`
- `default`, `forced`, `selected`
- Subtitle-specific: `format`, `key` (external), `hearingImpaired`, …
- Video-specific: `bitDepth`, `chromaSubsampling`, `colorSpace`, HDR indicators, …

## 6. Playback-Related Endpoints

### 6.1 Decision

```
GET /video/:/transcode/universal/decision
```

Client advertises capabilities; server returns decision codes and selected streams.

### 6.2 Start Stream

```
GET /video/:/transcode/universal/start.m3u8   (or .mpd / binary)
```

Common parameters:

- `path` — metadata key or full path
- `mediaIndex`, `partIndex`
- `protocol` — `hls` / `dash` / …
- `directPlay`, `directStream`, `directStreamAudio` (0/1)
- `session` — unique session id
- `offset` — start position (ms)
- `maxVideoBitrate`, `videoResolution`, `videoQuality`
- `subtitleSize`, `audioBoost`
- `subtitles` — `auto` / `burn` / …
- `location` — `lan` / `wan`
- Client capability profile extras

### 6.3 Direct Part Access

When Direct Play is possible:

```
{serverBase}{part.key}?X-Plex-Token=...
```

or the part file URL returned by metadata.

### 6.4 Timeline / Progress

```
POST /:/timeline   (or GET historically)
```

Parameters:

- `ratingKey` / `key`
- `state` — `playing` | `paused` | `stopped` | `buffering`
- `time` — current offset ms
- `duration`
- `continuing` (when stopping and advancing to next item)

Recommended cadence: ~10 s LAN, ~20 s cellular; always on state change. Debounce/throttle.

### 6.5 Scrobble / Unscrobble

```
PUT /:/scrobble?key=...&identifier=com.plexapp.plugins.library
PUT /:/unscrobble?...
```

Marks watched / unwatched without full history entry semantics of timeline.

## 7. Images

Transcode endpoint (common pattern):

```
GET /photo/:/transcode?url=...&width=...&height=...&minSize=1&upscale=1
```

Also direct art paths from metadata (`thumb`, `art`, `poster`, `grandparentThumb`, …). Always request display-appropriate sizes.

## 8. Playlists & Collections

- List / create / edit playlists under `/playlists`
- Collections appear as metadata type 18; items via children or dedicated collection endpoints

## 9. Sessions (Active Playback)

```
GET /status/sessions
```

Useful for debugging and multi-client awareness; not required for basic single-client playback.

## 10. Error Semantics (Client Handling)

| HTTP | Typical meaning | Client action |
|------|-----------------|---------------|
| 401 | Token invalid / missing | Clear session, re-auth |
| 403 | Permission denied | Surface friendly message |
| 404 | Item gone | Refresh library / show unavailable |
| 5xx / timeout | Server / network | Retry with backoff, fallback connection |

## 11. Implementation Notes for iOS

- Prefer `URLSession` with structured concurrency
- Always attach cancellation handlers
- Decode into **API DTOs**, map to **domain models**
- Never let raw `MediaContainer` XML/JSON leak into ViewModels
- Log request paths and status codes; **redact tokens**
