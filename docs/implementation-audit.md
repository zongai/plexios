# Implementation Audit vs 完整开发任务

Audit date: 2026-09-27. Honest status of scaffold vs full product requirements.

Legend: **Done** · **Partial** · **Missing**

---

## 1. Project foundations

| Requirement | Status | Notes |
|-------------|--------|-------|
| Native Swift / SwiftUI only | **Done** | No Python/Kodi |
| Swift Concurrency / Observation | **Done** | async/await, `@Observable` |
| AVFoundation / AVKit | **Done** | PlaybackEngine + PlayerLayerView |
| URLSession + Network.framework | **Done** | HTTPClient, NetworkPathMonitor |
| Keychain for token | **Done** | KeychainStore + AuthenticationService |
| SwiftData / SQLite | **Partial** | PersistenceController is stub; ResponseCache used instead |
| OSLog | **Done** | LogRouter |
| MediaPlayer (Now Playing) | **Done** | NowPlayingController + RemoteCommandController |
| BackgroundTasks | **Missing** | Not used |
| Phase 0 docs (7 files) | **Done** | under `artifacts/docs/` |

---

## 2. Authentication (§6)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Plex PIN auth | **Done** | AuthenticationService + SignInView |
| Token storage in Keychain only | **Done** | |
| Session restore | **Done** | bootstrap → restoreSession |
| Sign out | **Done** | Settings |
| Token invalid handling | **Partial** | Mapped to PlexError; no automatic force re-login UI flow everywhere |

---

## 3. Server discovery (§7)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Account → servers list | **Done** | `/api/v2/resources` |
| Connection candidates + probe | **Done** | rankConnections + latency |
| LAN / WAN / Relay preference | **Done** | rankScore |
| Multi-server select | **Done** | Settings picker |
| Network change refresh | **Done** | startObservingNetworkChanges |
| Auto fallback on failure | **Partial** | Rank on discover; mid-session connection failover not fully automatic |

---

## 4. API layer (§8)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Unified client + headers | **Done** | PlexAPIClient |
| JSON decoding | **Done** | |
| XML decoding | **Partial** | Comment only; PMS paths use JSON Accept |
| Timeout | **Partial** | URLSession defaults only |
| Retry | **Missing** | No automatic retry policy |
| Logging + redaction | **Done** | LogRedaction |
| Views never call API directly | **Done** | Repositories / services |

---

## 5. Data models (§9)

| Model | Status | Notes |
|-------|--------|-------|
| PlexServer / User / Pin | **Done** | |
| PlexLibrary / Hub | **Done** | |
| PlexMetadata (movie/show/season/episode) | **Done** | Unified type instead of separate PlexMovie/Show |
| PlexMedia / Part / Stream | **Done** | |
| PlexCollection | **Missing** | |
| PlexPlaylist | **Missing** | |
| API vs Domain separation | **Done** | PlexAPIModels + Mapper + PlexModels |
| Persistence models | **Missing** | SwiftData schema empty |

---

## 6. Home (§10)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Hubs from server | **Done** | HubRepository + HomeView |
| Horizontal rails | **Done** | HubRailView |
| Async image + cache | **Done** | ImagePipeline |
| Lazy loading | **Done** | LazyVStack / LazyHStack |
| Pull to refresh | **Done** | |
| Skeleton / empty / error | **Done** | |
| Collections / Playlists sections as features | **Partial** | Only if PMS hubs return them; no dedicated Features |

---

## 7. Library (§11)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Movies / Shows grids | **Done** | Generic grid by library type |
| Music-specific UI | **Missing** | Library type shown; no artist/album UI |
| Pagination | **Done** | LibraryGridViewModel loadMore |
| Movie → detail → play | **Done** | |
| Show → Season → Episode → play | **Done** | |

---

## 8. Movie detail (§12)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Backdrop, title, year, rating, duration | **Done** | |
| Genres, summary, directors, actors | **Done** | |
| Writers, studio | **Done** | Added in audit fix |
| Media info | **Done** | |
| Play / Resume | **Done** | |
| Mark watched / unwatched | **Done** | UI + engine (audit fix) |
| Add/remove favorite | **Missing** | No API or UI |

---

## 9. TV (§13)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Show / Season / Episode hierarchy | **Done** | |
| Episode detail + play | **Done** | |
| Auto-play next episode | **Missing** | Not implemented |

---

## 10. Search (§14)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Debounce + cancel | **Done** | 350ms |
| Grouped results | **Done** | Hub sections |
| Loading / empty | **Done** | |
| Actor / collection specific UX | **Partial** | Relies on server hub grouping |

---

## 11. Playback (§15)

| Requirement | Status | Notes |
|-------------|--------|-------|
| PlaybackEngine owns AVPlayer | **Done** | |
| Direct Play → Stream → Transcode | **Done** | PlaybackDecisionEngine + reasons |
| Capability matrix | **Done** | IOSCapabilities |
| URL builder (file + universal HLS) | **Done** | |
| Audio track selection | **Partial** | Fixed forced ID pass-through in audit; still restarts stream |
| Subtitle selection / burn-in | **Partial** | Same; native side-load limited |
| Timeline reporting | **Done** | Throttled |
| Resume from viewOffset | **Done** | |
| Scrobble on complete | **Done** | |
| PiP / AirPlay / Remote commands | **Done** | Phase 5 |
| Interruptions / route change | **Done** | |

---

## 12. Features directories (architecture §5)

| Folder | Status |
|--------|--------|
| Home, Libraries, Movies, Shows, Search, Player, Settings | **Implemented** |
| Collections | **Empty** |
| Playlists | **Empty** |
| Favorites | **Empty** |
| Media/Downloads | **Empty** |
| Media/Audio, Subtitles, Transcoding | **Empty dirs** (logic lives under Playback/) |

---

## 13. iPad / A11y / Cache

| Requirement | Status | Notes |
|-------------|--------|-------|
| NavigationSplitView iPad | **Done** | AdaptiveRootView |
| Accessibility labels | **Partial** | Cards, PIN, some buttons |
| Dynamic Type | **Partial** | System fonts; not all layouts stress-tested |
| Dark Mode | **Done** | Semantic colors |
| ImagePipeline + ResponseCache | **Done** | |
| Offline banner | **Done** | |

---

## 14. Testing

| Requirement | Status | Notes |
|-------------|--------|-------|
| Unit tests (decision, cache, mapper, errors, URLs, models) | **Done** | 10 test files |
| UI tests | **Missing** | |
| Integration automation | **Missing** | Manual plan in test-plan.md |
| Release checklist | **Done** | docs/release-checklist.md |

---

## Critical bugs fixed during this audit

1. **Audio/subtitle switch ignored forced stream IDs** — `play` now accepts `forcedAudioId` / `forcedSubtitleId`; select methods pass them through.
2. **Movie detail lacked Mark watched/unwatched** — buttons added; call TimelineReporter via PlaybackEngine.
3. **Writers / studio missing on movie detail** — displayed when present.
4. **PersistenceController fatalError on empty schema** — soft stub, no crash.

---

## Recommended next work (priority)

1. Collections / Playlists API + UI  
2. Favorites rate endpoints  
3. Next-episode autoplay  
4. HTTP retry + richer XML fallback  
5. Music library browse  
6. Real SwiftData models if offline is required  
7. UI tests for auth + play smoke path  

This scaffold is a **solid vertical slice** (auth → browse → play → native media → cache → iPad), not a feature-complete Plex client relative to the full task document.
