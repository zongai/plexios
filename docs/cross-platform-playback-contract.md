# Cross-Platform Playback Contract Specification

**Status:** Adopted  
**Scope:** iOS · Android TV · Windows  
**Principle:** Unify *playback semantics* and *domain model*, not the playback kernel.

> VLC / LibVLC is a **capability-gap fallback**, never the default primary player.

Related docs: `multi-platform-contracts.md` (identity, discovery, capabilities sketch), `plex-playback.md` (iOS reference behavior).

---

## 1. Architecture layers

```text
                 ┌───────────────────────────┐
                 │      Plex Domain Layer     │
                 │ MediaItem · Decision ·     │
                 │ Preferences · Tracks ·     │
                 │ State · Timeline · Session │
                 │ Capability · Errors        │
                 └─────────────┬─────────────┘
                               │
                      Cross-platform Contract
                      (this document)
                               │
                 ┌─────────────┴─────────────┐
                 │   Platform Adapter only    │
                 └─────────────┬─────────────┘
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
       iOS                 Android TV              Windows
   AVPlayer +             ExoPlayer /              MF +
   MobileVLCKit*          Media3 (+ LibVLC*)       LibVLC*
```

`*` Only when Decision selects the fallback backend.

| Layer | Shared across platforms? | Notes |
|-------|--------------------------|--------|
| Domain model + Decision rules | **Yes (semantics)** | Language-specific types OK |
| Player Contract (methods/events/state) | **Yes (semantics)** | Separate Swift / Kotlin / C# interfaces |
| Backend (AVPlayer, Exo, MF, VLC) | **No** | Never leak into UI / Session |
| Surface / PiP / AirPlay / AudioFocus | **No** | Platform-only |

---

## 2. Backend policy

| Platform | Primary | Fallback | Policy |
|----------|---------|----------|--------|
| **iOS** | AVPlayer | MobileVLCKit | System first for PiP / AirPlay / power; VLC for container/codec/subtitle gaps |
| **Android TV** | ExoPlayer (Media3) | *Not in phase 1* | Do **not** add LibVLC until measured ExoPlayer failures justify it |
| **Windows** | Media Foundation | LibVLC / LibVLCSharp | Keep dual-backend router |

Decision output must include:

```text
backend: system | vlc
mode:    directPlay | directStream | transcode
reason:  human-readable + machine tag
```

---

## 3. MediaPlayer Contract

Each platform implements an equivalent interface (names may differ; **behavior must not**).

### 3.1 Commands

| Operation | Semantics |
|-----------|-----------|
| `load` / `prepare(MediaItem \| PlaybackRequest)` | Resolve URL from Decision; do not auto-`play` unless request says so |
| `play()` | Start or resume |
| `pause()` | Pause; keep position |
| `stop()` | Tear down session; reset position reporting |
| `seek(to:)` | Target position; see §5 time units |
| `setRate(_:)` | 0.5 … 2.0 typical; 1.0 = normal |
| `setVolume(_:)` | Linear **0.0 … 1.0** (player volume, not system ringer) |
| `selectAudioTrack(id)` | Apply preferred or user pick; idempotent |
| `selectSubtitleTrack(id \| null)` | `null` / off disables subs |

### 3.2 Read model

| Property | Type (contract) | Notes |
|----------|-----------------|--------|
| `state` | PlaybackState | §4 |
| `position` | seconds (Double) | Also allow ms internally; convert at boundary |
| `duration` | seconds (Double) | 0 if unknown |
| `bufferedPosition` | seconds (Double) | Optional; 0 if unknown |
| `rate` | Double | Actual applied rate |
| `volume` | Double 0…1 | |
| `audioTracks` | [MediaTrack] | §6 |
| `subtitleTracks` | [MediaTrack] | §6 |
| `activeBackend` | `system` \| `vlc` | For diagnostics only |

### 3.3 Events (must surface to UI / Timeline)

```text
stateChanged(PlaybackState)
timeChanged(position, duration)     // ≥ 2 Hz while playing recommended
tracksChanged()
bufferingChanged(isBuffering)       // optional if folded into state
error(PlaybackError)
ended()                             // natural end of media
```

Platform mapping examples (internal → contract):

| Contract | iOS (typical) | Android (Exo) | Windows |
|----------|---------------|---------------|---------|
| buffering | timeControlStatus / VLC buffering | STATE_BUFFERING | Opening/Buffering |
| playing | playing + isPlaying intent | isPlaying | Playing |
| paused | paused | !isPlaying && READY | Paused |
| ended | itemDidPlayToEnd | STATE_ENDED | Ended |
| error | failed status / VLC error | PlaybackException | Error |

---

## 4. PlaybackState

Canonical set (all platforms must map into this):

```text
idle
loading          // prepare / opening network
ready            // can play, not yet playing (optional; may fold into paused)
buffering        // stalled for data; play intent may still be true
playing
paused
ended
stopped
error
```

**Rules:**

1. `buffering` is **not** `paused`. UI play/pause icon follows **play intent**, not buffering alone.  
2. `ended` fires once per media completion; autoplay-next is Session/Domain, not the raw player.  
3. `error` must carry a `PlaybackError` (§8); UI may offer retry / switch backend if Decision allows.

---

## 5. Time units

| Boundary | Unit |
|----------|------|
| **Engine / Contract integer fields** | **Milliseconds** (`positionMs`, `durationMs`, `bufferedMs`) — matches PMS timeline API |
| **UI display** | Convert to seconds / `h:mm:ss` at the view layer (locale-aware) |
| **Internal player APIs** | Platform native (`CMTime`, ExoPlayer ms, `TimeSpan`) — Adapter converts |

Rules:
- Public contract properties used for progress math and PMS reporting are **ms integers**.
- Never expose `CMTime` / ExoPlayer raw types / `TimeSpan` above the Adapter.
- Display formatting is UI-only and must use locale-aware formatters.

---

## 6. MediaTrack

Do **not** expose AVMediaSelectionOption, ExoPlayer Format, or libvlc track objects above the Adapter.

```text
MediaTrack
  id            string          // stable within current item session
  type          audio | subtitle | video
  language      string?         // BCP-47 or ISO 639 when known
  title         string?         // display title
  codec         string?
  isDefault     bool
  isSelected    bool
  isForced      bool
  isExternal    bool            // sidecar / non-embedded
  plexStreamId  int?            // link back to Plex stream id when known
```

**Selection policy (Domain, not player):**

1. User explicit choice (session)  
2. Preferences language priority list (first match wins)  
3. Plex `default` / `forced` flags  
4. Player / container default  

External text subs (SRT/ASS/VTT): download with token → attach → select when tracks appear; **retry until ready** (see iOS VLC path as reference behavior).

---

## 7. PlaybackDecision & Capability

### 7.1 Capability matrix (per backend)

Each backend on each platform publishes approximately:

```text
PlayerCapabilities
  containers[]
  videoCodecs[]
  audioCodecs[]
  subtitleFormats[]      // text vs bitmap
  hdrFormats[]
  maxWidth / maxHeight
  hardwareDecode
  directPlay / directStream / transcode
  externalSubtitle
  pip / airplay / drm / rateControl   // feature flags
```

### 7.2 Decision result

```text
PlaybackDecision
  backend          system | vlc
  mode             directPlay | directStream | transcode
  reason           string
  mediaIndex
  partIndex
  selectedAudioStreamId?
  selectedSubtitleStreamId?
  burnInSubtitles  bool
  videoBitrate?    // when capped / transcode
```

### 7.3 Evaluation order

```text
Plex Media (+ network class + preferences)
        → Capability check (primary backend)
        → directPlay?
        → directStream?
        → (optional) fallback backend capability
        → transcode
```

VLC is selected only when primary cannot satisfy without harmful transcode, or when user/settings force it.

---

## 8. Errors

```text
PlaybackError
  code             stable wire string (see table)
  message          localized or English technical
  recoverable      bool
  suggestedAction  retry | switchBackend | transcode | none
```

| Wire code | Meaning | Typical action |
|-----------|---------|----------------|
| `network` | Connectivity / timeout | retry |
| `mediaUnavailable` | 404 / missing item | none |
| `decode` | Player/decoder failure | switchBackend |
| `unsupported` | Codec/container not playable | transcode |
| `subtitle` | Subtitle attach/select failure | retry |
| `cancelled` | User or system cancel | none |
| `session` | Open/prepare/session failure | retry |
| `backend` | Engine init / switch failure | switchBackend |
| `track` | Audio track switch failure | retry |
| `unknown` | Unclassified | none |

Platform types: iOS `PlaybackError` + `PlaybackErrorCode` · Android `PlaybackError` · Windows `PlaybackError`.

---

## 9. Timeline / Session (Domain)

Independent of which backend is active:

| Concern | Contract |
|---------|----------|
| Report interval | ~ periodically while playing (platform may use 1s–10s) |
| Position source | Adapter `position` |
| State mapping | Adapter `state` → Plex timeline state |
| Stop / finish | Explicit stop vs natural `ended` |
| Autoplay next | Domain (NextEpisodeResolver), triggered on `ended` |

Adapters must not call Plex timeline APIs directly if a Session owner exists; they emit events only.

---

## 10. Platform implementation names (informative)

| Platform | Contract type (existing or target) | Primary | Fallback |
|----------|--------------------------------------|---------|----------|
| iOS | Behavior owned by `PlaybackEngine` (+ future thinner protocol) | AVPlayer | `VLCPlaybackBackend` |
| Android TV | `Media3PlayerShell` (+ future `MediaPlayerContract`) | ExoPlayer | *deferred* |
| Windows | `IPlayerEngine` | Media Foundation | `LibVlcPlayerEngine` |

---

## 11. Non-goals

- Sharing one source file across Swift / Kotlin / C#  
- Replacing all backends with LibVLC  
- Adding Android LibVLC in the same phase as contract alignment  
- Leaking player types into SwiftUI / Compose / WinUI view models beyond a narrow surface binding  

---

## 12. Compliance checklist (per platform)

- [ ] State machine maps to §4  
- [ ] Time boundary converts correctly (§5)  
- [ ] Tracks exposed only as MediaTrack-equivalent (§6)  
- [ ] Decision sets backend + mode + reason (§7)  
- [ ] Primary backend preferred; VLC only on gap (§2)  
- [ ] Events sufficient for UI + Timeline (§3.3)  
- [ ] Errors structured (§8)  
- [ ] No timeline calls inside raw backend if Session owns reporting (§9)  
