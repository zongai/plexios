# Implementation Plan

Strict phased delivery. **Do not start large-scale UI until Phase 0 docs are accepted and Phase 1 foundation exists.**

## Phase 0 — Research ✅ (this document set)

**Deliverables**

- [x] `docs/architecture.md`
- [x] `docs/plex-api.md`
- [x] `docs/plex-playback.md`
- [x] `docs/plex-networking.md`
- [x] `docs/data-model.md`
- [x] `docs/ios-capabilities.md`
- [x] `docs/implementation-plan.md`

**Exit criteria**

- Behavioral understanding of auth, discovery, connection ranking, media hierarchy, playback modes, timeline/scrobble
- Explicit non-goals (no Kodi port, no GPL code translation)
- Layered architecture agreed

---

## Phase Soft-Decode — App 内软解（规划中，稍后实现）

**策略：** 先试 AVPlayer → 失败再软解 / 服务器转码。

完整任务清单见 **`docs/soft-decode-plan.md`**（SD-0～SD-6）。

- 默认关闭软解，不改变现网 VP9→transcode 行为  
- 开启后：试播超时/失败 → Local Soft Decode → 再失败则 Transcode  
- 实现前需完成 FFmpeg vs VLCKit 选型与授权确认  

---

## Phase 1 — Foundation

**Goals**

- Xcode project (iOS 17+ recommended baseline; confirm deployment target)
- App entry, `AppEnvironment` DI root
- Logging categories (`network`, `plex`, `playback`, `cache`, `ui`, `database`)
- Keychain wrapper
- URLSession-based HTTP client skeleton (no Plex-specific logic yet)
- Persistence container skeleton (SwiftData or SQLite)
- Basic theme tokens (colors, typography, spacing)
- Unit test target wired

**Exit criteria**

- App launches on iPhone + iPad simulators
- Keychain round-trip test
- Logger redaction helper for tokens
- Empty Home shell compiles

---

## Phase 2 — Plex Core

**Goals**

1. **AuthenticationService**
   - PIN flow (strong PIN)
   - Token storage in Keychain
   - Sign-out / token invalidation
   - Optional: JWT device registration path scaffold

2. **ConnectionManager**
   - Fetch `/api/v2/resources`
   - Rank & probe candidates
   - Active server context
   - `NWPathMonitor` integration

3. **PlexAPIClient**
   - Header injection
   - JSON decoding
   - Error mapping → `PlexError`
   - Cancellation

4. **Domain models + mappers**
   - Server, Library, Metadata hierarchy, Media/Part/Stream

5. **Repositories**
   - Library, Metadata, Hub (read paths)

**Exit criteria**

- Sign-in with real Plex account
- Server list + successful library sections fetch
- Unit tests: auth state machine, connection ranking, DTO mapping
- No UI beyond debug / settings sign-in screen

---

## Phase 3 — Library Experience

**Goals**

- Home hubs (Continue Watching, Recently Added, …)
- Library browser (Movies / Shows grids)
- Movie detail
- Show → Season → Episode hierarchy
- Global search (debounced, cancellable, grouped results)
- Shared cards (`MovieCard`, `ShowCard`, `EpisodeCard`)
- Pull-to-refresh, skeleton, empty, error states
- ImagePipeline v1 (memory + disk, downsampling)

**Exit criteria**

- Full browse path on real server data
- Search usable
- iPhone + basic iPad layouts
- No playback yet (Play button can be stubbed)

---

## Phase 4 — Playback Engine (Critical)

**Goals**

1. `PlaybackDecisionEngine` with explicit reasons
2. `PlaybackEngine` owning `AVPlayer`
3. Direct Play path
4. Direct Stream path
5. Transcode path (HLS)
6. Audio track selection
7. Subtitle selection (native / side-load / burn-in request)
8. `PlaybackSession` + timeline reporting (throttled)
9. Resume from `viewOffset`
10. Mark watched / unwatched
11. Player SwiftUI UI (controls, timeline, next episode)

**Exit criteria**

- Decision unit tests for representative codec/container matrices
- End-to-end play of Direct Play title on LAN
- Forced transcode title plays
- Progress appears in Plex Continue Watching after session
- No View-owned player logic

---

## Phase 5 — Native iOS Media Features

**Goals**

- Picture in Picture
- AirPlay (system route picker)
- Now Playing info + lock screen controls
- Remote commands (play/pause/seek/next/previous)
- Background audio continuity
- Interruption handling (calls, other audio)

**Exit criteria**

- PiP works while multitasking
- AirPlay route change does not crash session
- Control Center reflects state

---

## Phase 6 — Cache & Performance

**Goals**

- Metadata / API response cache with TTL
- ImagePipeline hardening (dedupe, progressive if feasible, memory pressure)
- Scroll performance pass on large libraries
- Playback startup instrumentation
- Eliminate N+1 request patterns
- Main-thread work audit

**Exit criteria**

- Instruments traces show no obvious main-thread decode/network
- Home cold/warm metrics within targets in `ios-capabilities.md`

---

## Phase 7 — iPad / Polish

**Goals**

- `NavigationSplitView` adaptive layouts
- Inspector / multi-column detail where appropriate
- Accessibility (VoiceOver, Dynamic Type, Reduce Motion)
- Dark Mode refinement
- Loading / empty / error consistency
- Motion & hero transitions (subtle)
- Settings surface (account, playback quality, network prefs, cache)

**Exit criteria**

- Usable on iPad landscape/portrait without horizontal cramping
- Accessibility audit pass on primary flows

---

## Phase 8 — Testing & Hardening

**Goals**

- Expand unit + integration tests:
  - API client
  - Auth
  - ConnectionManager
  - Metadata parsers
  - Playback decision matrix
  - Stream selector
  - Cache
  - Playback session / timeline
- Snapshot tests for key cards (optional)
- Memory / leak checks around player lifecycle
- Failure injection (401, offline, relay-only)

**Exit criteria**

- CI green on unit tests
- Documented manual test checklist for device matrix
- Known limitations listed

---

## Cross-Cutting Rules (All Phases)

1. **Layer discipline** — fix bugs in the correct layer; no View → API shortcuts.
2. **One logical commit per feature** (`feat:`, `fix:`, `perf:`, `test:`).
3. **Cancellation** — every screen-bound Task must cancel on disappear.
4. **Tokens** — Keychain only; redact in logs.
5. **Decision priority**: correctness > Plex compatibility > native API > performance > maintainability > brevity > speed of coding.
6. **No GPL code translation** from plex-for-kodi; behavior reference only.
7. **No claiming “done” with mocks only** — real PMS verification required for auth, browse, and playback milestones.

---

## Immediate Next Step After Phase 0

Begin **Phase 1 — Foundation**:

1. Create Xcode project structure matching `architecture.md`
2. Implement `AppEnvironment`, logging, Keychain, networking skeleton
3. Add empty feature modules and test target
4. Stop and review before any Plex protocol code beyond stubs

Only after Phase 1 review proceeds to Phase 2 Plex Core.
