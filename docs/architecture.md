# Architecture — Plex iOS Native Client

## 1. Goals & Constraints

Build a **native iOS Plex Media Server client** that:

- Connects to user-owned / shared PMS instances
- Browses libraries, hubs, collections, playlists
- Plays media with correct Direct Play / Direct Stream / Transcode decisions
- Syncs watch state and resume positions
- Follows modern SwiftUI + Observation + Swift Concurrency practices

**Non-goals (Phase 0–8):**

- Porting Kodi / Python runtime
- Replicating Kodi UI
- Full offline download engine (architecture only reserved)
- Multi-user home switching beyond basic support

## 2. High-Level Layering

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI (Features + UI Components)                         │
│  Home · Libraries · Detail · Search · Player · Settings     │
└────────────────────────────┬────────────────────────────────┘
                             │ Intent / State
┌────────────────────────────▼────────────────────────────────┐
│  Feature Layer (ViewModels / @Observable models)            │
│  Ownership of screen state, loading, error, navigation      │
└────────────────────────────┬────────────────────────────────┘
                             │ Domain calls
┌────────────────────────────▼────────────────────────────────┐
│  Domain                                                     │
│  PlexRepository · SearchService · PlaybackEngine            │
│  ImagePipeline · ConnectionManager · AuthService            │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│  Infrastructure                                             │
│  PlexAPIClient · Keychain · Cache · Database · Network      │
│  OSLog · BackgroundTasks                                    │
└────────────────────────────┬────────────────────────────────┘
                             │
                    Plex Media Server / plex.tv
```

### Layer Responsibilities

| Layer | Owns | Must not own |
|-------|------|--------------|
| **SwiftUI Views** | Rendering, gestures, navigation, accessibility | Network, persistence, playback decisions, tokens |
| **ViewModels / Feature models** | Screen state, intents, Task lifecycle, error presentation | Raw HTTP, Keychain, AVPlayer setup |
| **Domain services** | Business rules, playback decision, connection selection | UI layout, direct View references |
| **Infrastructure** | HTTP, storage, system APIs | Business policy, UI state |

## 3. Recommended Module / Directory Layout

```
PlexiOS/
├── App/
│   ├── PlexApp.swift
│   └── AppEnvironment.swift          # DI root, shared services
├── Core/
│   ├── Networking/                   # URLSession wrappers, interceptors
│   ├── Persistence/                  # SwiftData / SQLite models & stores
│   ├── Logging/                      # OSLog categories
│   ├── Cache/                        # Memory + disk policies
│   └── Utilities/
├── Plex/
│   ├── Authentication/               # PIN / JWT flow, token storage
│   ├── Server/                       # Discovery, ConnectionManager
│   ├── API/                          # PlexAPIClient, endpoints, DTOs
│   ├── Models/                       # Domain models (not raw XML/JSON)
│   ├── Repositories/                 # Library, Metadata, Hub, Playlist
│   └── Services/                     # Search, ImagePipeline coordination
├── Media/
│   ├── Playback/                     # PlaybackEngine, Session, Decision
│   ├── Transcoding/                  # Decision helpers, session lifecycle
│   ├── Subtitles/
│   ├── Audio/
│   └── Downloads/                    # Future offline (stub interfaces)
├── Features/
│   ├── Home/
│   ├── Libraries/
│   ├── Movies/
│   ├── Shows/
│   ├── Search/
│   ├── Collections/
│   ├── Playlists/
│   ├── Player/
│   └── Settings/
├── UI/
│   ├── Components/
│   ├── Cards/
│   ├── Sections/
│   ├── Navigation/
│   └── Theme/                        # Colors, typography, spacing
└── Tests/
    ├── Plex/
    ├── Networking/
    ├── Playback/
    └── UI/
```

## 4. Core Domain Components

### 4.1 AuthenticationService

- PIN-based (and future JWT device) flow against `clients.plex.tv` / `plex.tv`
- Obtains long-lived or short-lived tokens
- Stores **only** in Keychain
- Publishes auth state (`signedOut` / `signedIn(token, user)`)
- Handles token invalidation (401 → force re-auth)

### 4.2 ConnectionManager

Responsibility chain:

```
Plex Account token
    → resources (servers)
    → connection candidates (local / remote / relay / custom)
    → reachability probes
    → preferred connection selection
    → active server context
```

Must react to `NWPathMonitor` changes (Wi-Fi ↔ Cellular ↔ Offline) without tearing down an active playback session abruptly.

### 4.3 PlexAPIClient

- Single entry point for all PMS + plex.tv HTTP
- Injects `X-Plex-Token`, client identification headers
- Supports JSON preferred (`Accept: application/json`)
- Retries, timeouts, cancellation via `URLSession` + Swift Concurrency
- Never called directly from Views

### 4.4 PlexRepository family

- `LibraryRepository`, `MetadataRepository`, `HubRepository`, `PlaylistRepository`, `SearchRepository`
- Memory → Disk → Network cascade
- Typed domain models (not raw DTOs)

### 4.5 PlaybackEngine

Central authority for:

1. Capability inspection (container, codecs, HDR, audio channels, subtitle format)
2. Decision: Direct Play → Direct Stream → Transcode
3. Session creation / timeline reporting
4. AVPlayer / AVPlayerItem lifecycle
5. Audio & subtitle track selection
6. PiP, AirPlay, Now Playing integration points

Views and ViewModels only send intents (`play`, `pause`, `seek`, `selectAudio`, `selectSubtitle`).

### 4.6 ImagePipeline

Dedicated pipeline (not scattered `AsyncImage`):

- Request deduplication
- Memory + disk cache
- Downsampling to display size
- Cancellation on view disappear
- Separate policies for poster / backdrop / episode thumb / actor

## 5. State Ownership Principles

Prefer **localized `@Observable` models** over a single giant `AppState`.

Suggested top-level environment objects / dependencies:

- `AppEnvironment` (services, factories)
- `AuthenticationState`
- `ServerConnectionState` (active server + connection quality)
- `PlaybackState` (current session only)

Feature ViewModels own their own loading / error / data slices.

## 6. Concurrency Model

- All I/O: `async/await`
- Actors for shared mutable state (connection cache, image cache, playback session)
- `@MainActor` only at UI / ViewModel boundaries
- Structured concurrency (`TaskGroup` for parallel connection probes)
- Explicit cancellation on view teardown (`.task { }` + `Task.checkCancellation()`)

## 7. Error Taxonomy (Domain)

```swift
enum PlexError: Error {
    case authentication(AuthenticationError)
    case network(NetworkError)
    case serverUnavailable
    case invalidResponse
    case decoding
    case playback(PlaybackError)
    case transcoding(TranscodingError)
    case mediaUnavailable
    case permission
}
```

UI maps these to localized, user-facing messages. Never surface raw `NSError` domains.

## 8. Mapping from plex-for-kodi (Behavioral Only)

| Concern | Kodi reference area (conceptual) | iOS design |
|---------|----------------------------------|------------|
| Auth & token | plex.py / account handling | AuthenticationService + Keychain |
| Host / connection | plex_hosts.py | ConnectionManager |
| Metadata graph | metadata.py | Domain models + Repositories |
| Playback decision | player.py / playback_utils.py | PlaybackDecisionEngine |
| Timeline / scrobble | player service | PlaybackSession reporter |
| Cache | cache.py / data_cache.py | Cache layer + ImagePipeline |

**Rule:** extract protocol behavior and decision criteria only. Do not translate Python module structure or Kodi UI patterns into Swift.

## 9. Evolution Path

| Phase | Focus |
|-------|-------|
| 0 | Research & docs (this document set) |
| 1 | Foundation (project, DI, logging, Keychain, networking skeleton) |
| 2 | Plex Core (auth, discovery, API client, models, repositories) |
| 3 | Library UI (Home, Libraries, Detail, Search) |
| 4 | Playback Engine (decision + AVPlayer + session) |
| 5 | Native media (PiP, AirPlay, Now Playing, background) |
| 6 | Cache & performance |
| 7 | iPad / polish / accessibility |
| 8 | Testing & profiling |

## 10. Design Invariants

1. No Plex Token in UserDefaults / plist / plain JSON files.
2. No View → API or View → Database shortcuts.
3. Playback decision lives exclusively inside `PlaybackEngine`.
4. Prefer Direct Play; escalate only when necessary.
5. Every network Task must be cancellable.
6. Architecture remains ready for offline metadata / downloads without rewriting the API layer.
