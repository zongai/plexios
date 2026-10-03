# Cross-Platform Playback Gap Analysis

**Against:** `cross-platform-playback-contract.md`  
**Codebases:** `PlexiOS/` · `AndroidTV/` · `PlexWindows/`  
**Date:** 2026-10-03  

Legend: **OK** aligned · **Partial** works but diverges · **Gap** missing or wrong layer · **N/A** not required yet

---

## 1. Executive summary

| Area | iOS | Android TV | Windows |
|------|-----|------------|---------|
| Dual backend (system + VLC) | **OK** | **Gap** (Exo only; VLC deferred by policy) | **OK** |
| Explicit player contract interface | **Partial** (`PlaybackEngine` is god-object) | **Partial** (`Media3PlayerShell` only) | **OK** (`IPlayerEngine`) |
| PlaybackState set | **Partial** | **Partial** | **Partial** |
| Time unit boundary | **Partial** (ms-centric) | **Partial** (ms-centric) | **Partial** (ms-centric) |
| MediaTrack model | **Partial** (PlexStream + VLC indexes) | **Partial** (`PlayerTrack`) | **Partial** (`TrackInfo`) |
| Decision + capabilities | **OK** | **OK** (port) | **OK** (port) |
| Language preference → auto track | **OK** (with VLC retry) | **Partial** | **Partial** |
| External subtitle retry | **OK** (VLC path) | **Gap** | **Partial** |
| Timeline/Session separation | **Partial** | **Gap** | **Partial** |
| Capability matrix per backend | **Partial** | **Partial** (single matrix) | **Partial** (WindowsDefault; not per-backend) |

**Recommended next work:** align state enums + MediaTrack fields + document ms↔seconds boundary; thin iOS `PlaybackEngine` toward protocol; Android stay on ExoPlayer and only fill Decision/Timeline parity.

---

## 2. Contract surface (commands / events)

### 2.1 iOS — `PlaybackEngine` + backends

| Contract item | Status | Notes |
|---------------|--------|--------|
| prepare / play / pause / stop | **OK** | `play`, `togglePlayPause`, `stop` |
| seek | **OK** | `seek(toMs:)` |
| setRate / setVolume | **OK** | Applied to AVPlayer + VLC |
| select audio / subtitle | **OK** | Plex stream id; AV + VLC paths |
| state + isPlaying intent | **Partial** | `PlaybackSessionState` + separate `isPlaying` (good for buffering icon) |
| events | **Partial** | Observable properties / callbacks; not a single event bus |
| activeBackend | **OK** | `activePlaybackBackend` |

**Gap:** No small `MediaPlayerProtocol`; UI talks to `PlaybackEngine` which also owns Decision, Timeline, NowPlaying, autoplay. Harder to test backends in isolation.

### 2.2 Android TV — `Media3PlayerShell`

| Contract item | Status | Notes |
|---------------|--------|--------|
| play / pause / seek | **OK** | ms seek |
| setRate / setVolume | **Gap** | Not first-class on shell |
| select audio / subtitle | **Partial** | Track override by group/index |
| state Flow | **Partial** | Idle/Buffering/Ready/Playing/Ended/Error — no `paused`/`loading`/`stopped` |
| events | **Partial** | StateFlow only |
| backend switch | **N/A** | Single ExoPlayer |

**Gap:** Shell is Exo-specific (`exoPlayer` leaked). Need a `MediaPlayerContract` facade before any second backend.

### 2.3 Windows — `IPlayerEngine`

| Contract item | Status | Notes |
|---------------|--------|--------|
| PrepareAsync / Play / Pause / StopAsync / SeekAsync | **OK** | Closest to contract |
| Volume / mute | **OK** | |
| SelectAudio / SelectSubtitle | **OK** | stream id |
| State + events | **OK** | StateChanged, PositionChanged, TracksChanged, ErrorOccurred |
| BackendChanged | **OK** | Router dual backend |
| setRate | **Gap** | Not on interface |

**Strongest structural match** to the contract among the three.

---

## 3. PlaybackState mapping

| Contract | iOS `PlaybackSessionState` | Android `PlayerState` | Windows `PlayerState` |
|----------|----------------------------|------------------------|------------------------|
| idle | idle | Idle | Idle |
| loading | loading | — | Opening (**Partial**) |
| ready | — | Ready | — |
| buffering | buffering | Buffering | Buffering |
| playing | playing | Playing | Playing |
| paused | paused | — (uses Ready when not playing) | Paused |
| ended | ended (if present) | Ended | Ended |
| stopped | — | — | Stopped |
| error | error | Error | Error |

**Action:** Adopt one shared enum vocabulary in docs and map explicitly in each Adapter. Android should distinguish **Paused** vs **Ready**. iOS/Windows should document Opening≡loading, Stopped≡stopped.

---

## 4. Time units

| Platform | Dominant unit in player API | Plex timeline |
|----------|----------------------------|---------------|
| iOS | **ms** (`positionMs`, `durationMs`) | ms |
| Android | **ms** (`seekTo(ms)`) | ms (if/when wired) |
| Windows | **ms** (`PositionMs`, `DurationMs`) | ms |

Contract prefers **seconds at the semantic boundary** for UI math; all three are consistently **ms-native**, which is fine if documented:

> **Amendment in practice:** Timeline and player engines use **milliseconds integers**; UI may display seconds. Cross-platform docs should state **ms as on-the-wire/player integer unit** to match PMS, and treat “seconds in contract prose” as illustrative.

**Gap:** None critical if we amend the contract note to “ms integer for engine + PMS; seconds optional for UI.” Prefer **not** introducing a dual API without need.

---

## 5. MediaTrack / stream model

| Field (contract) | iOS | Android `PlayerTrack` | Windows `TrackInfo` |
|------------------|-----|------------------------|---------------------|
| id | Plex stream id / VLC index | string id | stream id |
| type | via streamType | Audio / Text | present |
| language | PlexStream | language? | check implementation |
| title | displayTitle | label | |
| codec | optional on PlexStream | — | |
| isDefault / isForced / isExternal | PlexStream flags | selected only | Partial |
| isSelected | selectedAudioId / VLC index | selected | |

**Gap:** Normalize a single field list in each codebase’s DTO used by UI (even if filled from PlexStream). Android lacks forced/external; Windows TrackInfo should be verified for language + external.

---

## 6. Decision & capabilities

| Item | iOS | Android | Windows |
|------|-----|---------|---------|
| PlaybackDecisionEngine | **OK** | **OK** (port) | **OK** (port) |
| ClientCapabilities | **OK** | AndroidTVDefault | WindowsDefault |
| Per-backend capability (system vs VLC) | **Partial** | **Gap** | **Partial** |
| backend field on decision | **Partial** (engine chooses VLC path) | **Gap** | Router preferred backend |
| preferred audio/sub languages | **OK** | **OK** on prefs | **Partial** on prefs |
| burn-in / transcode reasons | **OK** | **OK** | **OK** |

**Gap:** Explicit `decision.backend = system | vlc` on all platforms would make UI diagnostics and logging match the contract. Today iOS/Windows infer from active engine.

---

## 7. Subtitles & audio preference application

| Behavior | iOS | Android | Windows |
|----------|-----|---------|---------|
| Apply language priority at start | **OK** | **Partial** | **Partial** |
| Retry when tracks appear late (VLC) | **OK** | **N/A** | **Partial** |
| External SRT download + attach + retry | **OK** (VLC) | **Gap** | **Partial** |
| AVPlayer/Exo/MF embedded selection | **OK** | **Partial** | **Partial** |

iOS recently hardened VLC audio/subtitle races; that behavior is the **reference** for fallback backends.

---

## 8. Timeline / Session

| Item | iOS | Android | Windows |
|------|-----|---------|---------|
| TimelineReporter | **OK** | **Gap** / minimal | **OK** (`TimelineReporter`) |
| Owned outside raw decoder | **Partial** (inside PlaybackEngine) | **Gap** | **Partial** |
| Autoplay next episode | **OK** | check app layer | **OK** (`NextEpisodeResolver`) |

**Gap:** Android needs a Session/Timeline owner wired to player state events before feature parity with Plex progress sync.

---

## 9. Backend policy compliance

| Policy | Compliance |
|--------|------------|
| iOS system first + VLC fallback | **OK** |
| Windows MF + LibVLC | **OK** |
| Android Exo only; no LibVLC yet | **OK** (by design) |
| VLC not default primary | **OK** on all current shipping paths |

No change recommended to force LibVLC onto Android in this phase.

---

## 10. Prioritized alignment backlog

### P0 — Semantics (low risk, high clarity)

1. Document **ms** as engine/timeline integer unit in contract (amend §5).  
2. Align state enum names + mapping tables in code comments or small mappers.  
3. Add `Paused` to Android player state (Ready ≠ Paused).  

### P1 — Model parity

4. Introduce UI-facing `MediaTrack`-equivalent on each platform with full flags.  
5. Put `backend` + `mode` + `reason` on a shared decision DTO shape everywhere.  
6. Windows: add `Rate` to `IPlayerEngine` if product needs speed control parity.  
7. Android: `setVolume` / `setRate` on shell or contract facade.  

### P2 — Structural

8. iOS: extract `MediaPlayerProtocol` from `PlaybackEngine`; keep Engine as orchestrator (Decision + Session + NowPlaying).  
9. Android: `MediaPlayerContract` interface implemented by `Media3PlayerShell` only.  
10. Android: TimelineReporter + progress sync.  
11. Per-backend Capability objects (system vs vlc) feeding Decision.  

### P3 — Only if product requires

12. Android LibVLC adapter after real-world ExoPlayer failure analysis.  
13. Unified error code enum across three apps.

---

## 11. Explicit non-actions

- Do **not** replace AVPlayer / ExoPlayer / MF with VLC-only stacks.  
- Do **not** share one protocol source file across languages.  
- Do **not** add Android LibVLC in the same sprint as contract docs.  

---

## 12. Reference “best” current pieces to copy

| Concern | Copy from |
|---------|-----------|
| Interface shape | Windows `IPlayerEngine` |
| Orchestration + VLC track retry | iOS `PlaybackEngine` + `VLCPlaybackBackend` |
| Lean Exo integration | Android `Media3PlayerShell` |
| Decision portability | All three `PlaybackDecisionEngine` ports (keep in sync) |
