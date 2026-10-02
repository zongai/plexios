# Multi-Platform Plex Client — Architecture & Migration Plan

**Status:** Approved 2026-10-02  
**Branch:** `feature/multi-platform`  
**Baseline:** Existing native iOS client (Swift / SwiftUI) remains the source of truth for behavior.

## 1. Goals

Extend the completed iOS Plex client into a multi-platform family without sacrificing platform-native UX:

```
                    Plex Server
                         │
                  Unified Plex Core
                         │
        ┌────────────────┼────────────────┐
        │                │                │
      iOS            Android TV        Windows
   SwiftUI         Compose for TV      WinUI 3
   AVPlayer/VLC/NME   Media3/ExoPlayer  MF / LibVLC / FFmpeg
```

- **iOS / iPadOS**: keep existing implementation; only progressive extraction of shared logic.
- **Android TV / Google TV 12+**: native Kotlin + Jetpack Compose for TV, remote-first (D-pad).
- **Windows 10/11**: native C# + WinUI 3 desktop app (not WebView).
- Shared: Plex API semantics, domain models, auth flow, server discovery/ranking, playback decision, session/timeline reporting, search, next-episode logic.
- **Not shared**: UI, theme implementation, player backends, secure storage, platform capabilities matrix.

## 2. Non-Goals / Hard Constraints

- Do **not** port SwiftUI views to other platforms.
- Do **not** introduce `if iOS / if Android / if Windows` into core business logic.
- Do **not** break existing iOS build or features at any step.
- Do **not** force a single player technology across platforms.
- Token must never be stored in plain text / logs / git on any platform.
- Prefer Plex Server transcode over heavy client-side software decoding when the platform player cannot Direct Play.

## 3. Target Directory Layout (long-term)

```
PlexClient/                          # eventual monorepo root (or keep PlexiOS + sibling folders)
├── Shared/                          # language-agnostic contracts + reference implementations
│   ├── contracts/                   # OpenAPI / JSON Schema / capability interfaces
│   ├── models/                      # canonical domain model definitions
│   └── docs/                        # request/response examples, decision algorithms
├── iOS/                             # current PlexiOS (progressive move)
├── AndroidTV/
└── Windows/
```

Until the monorepo is fully restructured, extraction happens **inside** the existing iOS tree first (interfaces + pure logic), then sibling projects consume the contracts.

## 4. Shared Core Contracts (Phase 1 deliverables)

### 4.1 Domain Models (canonical)

Already present in `Plex/Models/PlexModels.swift` and largely platform-agnostic:

- `PlexUser`, `PlexPin`
- `PlexServer`, `PlexConnection` (+ ranking score)
- `PlexLibrary`, `PlexLibraryType`
- `PlexHub`
- `PlexMetadata` (+ type enum covering movie/show/season/episode/artist/album/track/collection/playlist)
- `PlexMedia` → `PlexPart` → `PlexStream`
- `PlexRole`

These become the **source of truth**. Other platforms implement equivalent types (Kotlin data classes / C# records) that match the same JSON shapes and semantics.

### 4.2 Plex API Surface

Required endpoints (already implemented on iOS):

| Area | Operations |
|------|------------|
| Auth | Create PIN, Poll PIN |
| Discovery | Resources (servers + connections) |
| Library | Sections, All (paginated) |
| Home | Hubs |
| Metadata | Item, Children, Related, Continue |
| Collections / Playlists | List + children/items |
| Search | Hub search |
| Actions | Rate |
| Identity | Probe |

All requests carry standard `X-Plex-*` client identity headers + token.

### 4.3 Authentication Flow

```
App → POST /api/v2/pins → present code → poll until authToken → store securely → restore on launch
```

Platform secure storage:
- iOS → Keychain
- Android → Keystore + EncryptedSharedPreferences
- Windows → Credential Manager + DPAPI

### 4.4 Server Discovery & Ranking

1. Fetch resources with `includeHttps=1&includeRelay=1&includeIPv6=1`
2. Probe reachable connections (latency)
3. Rank: prefer local, prefer non-relay, prefer HTTPS on remote, etc. (existing `rankScore` logic is the reference)
4. Maintain active server + preferred connection; react to network path changes without killing active playback.

### 4.5 Playback Decision

Inputs:
- Media / Part / Streams (codecs, container, HDR, channels, subtitles…)
- ClientCapabilities (platform-declared)
- Network class + user preferences (max bitrate, prefer system player, etc.)

Output:
```
PlaybackDecision {
  mode: directPlay | directStream | transcode
  reason: String
  mediaIndex, partIndex
  selectedAudioStreamId, selectedSubtitleStreamId
  burnInSubtitles
  maxBitrateKbps?
}
```

Priority: Direct Play → Direct Stream → Transcode.

### 4.6 ClientCapabilities (per-platform declaration)

```
Capabilities {
  containers, videoCodecs, audioCodecs, subtitleFormats
  maxResolution, hdrProfiles, dolby
  directPlay, directStream, transcode, hls
  pip, airPlay, backgroundPlayback, remoteControl  // platform flags
}
```

iOS already has `IOSCapabilities`. Android TV and Windows will supply their own matrices.

### 4.7 Playback Session & Reporting

```
PlaybackSession {
  sessionId, mediaId, serverId
  position, duration, state
  volume, audioTrack, subtitleTrack
  updatedAt
}
```

States: START → PLAYING → (periodic progress) → PAUSED / RESUMED → STOP / COMPLETED.

Timeline reporting must be rate-limited and resilient to temporary network loss (do not tear down player solely because reporting fails).

### 4.8 Next-Episode Logic

Reference implementation already exists on iOS:
- Same season next episode
- Cross-season first episode of next season
- Handle specials, missing episodes, playlists, watched state

## 5. Platform-Specific Boundaries

| Concern | iOS | Android TV | Windows |
|---------|-----|------------|---------|
| UI toolkit | SwiftUI | Compose for TV | WinUI 3 |
| Primary player | MobileVLCKit (DP) + AVPlayer (HLS/PiP/AirPlay) + NME experimental | Media3 / ExoPlayer | Media Foundation → LibVLC/FFmpeg fallback |
| Secure storage | Keychain | Keystore + Encrypted prefs | Credential Manager / DPAPI |
| Remote input | Touch + Lock Screen + AirPlay | D-pad / remote | Keyboard + Media Keys + mouse |
| Image cache | ImagePipeline (memory+disk) | Coil / Glide equivalent | native cache |
| Build | XcodeGen + xcodebuild → IPA | Gradle → APK/AAB (TV) | MSBuild / dotnet → MSIX |

## 6. Migration Phases (approved; Windows prioritized 2026-10-02)

### Phase 1 — Formalize Shared Core ✅
- Document all contracts (this file + multi-platform-contracts.md).
- Extract `PlexAPIProtocol` inside iOS; domain services depend on contract.
- Keep every change iOS-buildable.

### Phase 2 — Windows skeleton ✅ (scaffold complete)
- WinUI 3 project at `artifacts/PlexWindows/`.
- PIN auth (DPAPI), server discovery/ranking, Fluent sidebar shell, Home hubs.
- PlaybackDecisionEngine + IPlayerEngine + Media Foundation stub + URL builder.

### Phase 3 — Windows full playback & libraries (player polished)
- ✅ Libraries (Movies / TV / Music), Detail, Search, Favorites
- ✅ PlaybackDecision + URL builder + next-episode
- ✅ MediaFoundationPlayerEngine → MediaPlayer + MediaPlayerElement
- ✅ Audio/Subtitle ComboBox, volume/mute, chrome auto-hide, timeline report
- ✅ Keyboard: Space / J L / ↑↓ / M / Esc / Media keys
- ⏳ Poster image binding polish; LibVLC fallback; MSIX CI

### Phase 4 — Android TV skeleton (done)
- ✅ `artifacts/AndroidTV/` — Kotlin + Compose for TV, Leanback launcher
- ✅ PIN auth (EncryptedSharedPreferences), server discover/rank/probe
- ✅ Home hubs, Libraries grid, Media3/ExoPlayer shell
- ✅ PlaybackDecisionEngine + URL builder (DP / DS / Transcode)
- ⏳ Phase 5: Detail/Search/Collections, tracks, next-episode, timeline

### Phase 5 — Android TV full playback (done)
- ✅ Detail / Search / Collections / Playlists
- ✅ Coil posters, next-episode, timeline report
- ✅ Home nav chips → Libraries / Search / Collections / Playlists

### Phase 6 — Cross-platform hardening
- Unified settings surface, CI path filters, release artifacts, capability matrix tests.

## 7. Build & CI Rules

- iOS: continue `xcodegen generate` + unsigned IPA workflow. Never break existing path.
- Android TV: `./gradlew assembleRelease` → arm64-v8a TV APK with Leanback.
- Windows: MSIX (x64) + debuggable desktop run.
- CI: path-filtered workflows so a change on one platform does not force all three builds.
- Tag `v*` → publish all three artifacts to the same GitHub Release.

## 8. Quality Gates (every phase)

1. iOS still builds and core flows work.
2. No token leakage.
3. UI never parses raw Plex XML/JSON.
4. Playback decision remains explainable (reason string).
5. New platform code lives in its own tree; no mixed platform conditionals in Shared.

## 9. Immediate Next Actions

1. ✅ Phase 1 complete (contracts + PlexAPIProtocol).
2. ✅ Windows skeleton scaffolded under `artifacts/PlexWindows/`.
3. Next: Phase 3 — wire real MediaPlayerElement, library browsing, detail pages, search.
4. Then Android TV (Phase 4).

---

*This document is the living plan. Update it when phase boundaries or technical choices change.*
