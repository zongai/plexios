# Plex Playback — Decision, Streams & Session

Playback is the highest-risk and highest-value subsystem. All logic belongs in `PlaybackEngine` + supporting decision/session types; Views only issue intents.

## 1. Delivery Modes

| Mode | What happens | Server cost | When chosen |
|------|--------------|-------------|-------------|
| **Direct Play** | Original file bytes delivered as-is | Minimal | Container + video + audio + subtitle all natively supported by client |
| **Direct Stream** | Video/audio streams remuxed into a client-friendly container; streams themselves untouched | Low | Codecs OK, container (or packaging) not |
| **Transcode** | One or more streams re-encoded (and possibly container changed) | High (CPU/GPU) | Incompatible codec, bitrate/resolution limit, burn-in subtitle, etc. |

Priority for the client: **Direct Play → Direct Stream → Transcode**.

## 2. Decision Inputs

### 2.1 Media side

From `Media` / `Part` / `Stream`:

- Container (`mkv`, `mp4`, `avi`, …)
- Video: codec, profile, level, resolution, bit depth, HDR / Dolby Vision, frame rate, bitrate
- Audio: codec, channels, bitrate, layout
- Subtitle: codec/format (`srt`, `ass`, `pgs`, `vtt`, …), forced/default, external vs embedded

### 2.2 Client side (iOS capabilities)

Maintain an explicit capability matrix (versioned with OS / device):

- Containers AVFoundation can open natively
- Video codecs / profiles (H.264, HEVC, AV1 where available, HDR10, Dolby Vision profiles supported by the SoC)
- Audio codecs & channel counts (AAC, AC3, EAC3, TrueHD, DTS, Atmos where applicable)
- Subtitle formats AVPlayer can render vs those requiring burn-in or side-loaded text tracks
- Max resolution / bitrate practical for the current network class

### 2.3 Network & server

- LAN vs WAN vs Relay
- Measured or declared bandwidth
- Server transcoder availability / hardware acceleration
- User quality preference (Original / Convert automatically / specific max bitrate)

## 3. Decision Algorithm (Conceptual)

```
func decide(media, part, streams, clientCaps, network, preferences) -> PlaybackDecision {
    if client can open container
       && client can decode video stream
       && client can decode selected audio
       && (no subtitle || client can render subtitle natively) {
        return .directPlay(url: partFileURL)
    }

    if client can decode video
       && client can decode audio
       && (container remap only, or audio/subtitle remux) {
        return .directStream(transcodeURL with directPlay=0, directStream=1, …)
    }

    // Otherwise request transcode with appropriate constraints
    return .transcode(transcodeURL with bitrate/resolution/subtitle burn parameters)
}
```

Every decision must be **explainable** for tests and diagnostics:

- “Direct Play unavailable: video codec HEVC Main 10 Level 5.1 not supported on this device”
- “Direct Stream selected: container mkv → mp4 remux; video+audio compatible”

## 4. Building Playback URLs

### 4.1 Direct Play

```
{serverBase}{part.key}?X-Plex-Token={token}&X-Plex-Client-Identifier=...
```

Or the absolute file URL when provided. Use `AVURLAsset` / `AVPlayerItem`.

### 4.2 Universal Transcoder (Direct Stream & Transcode)

Base path patterns:

```
/video/:/transcode/universal/decision
/video/:/transcode/universal/start.m3u8   (HLS)
```

Important query parameters (non-exhaustive):

| Param | Role |
|-------|------|
| `path` | Metadata key or path |
| `mediaIndex` / `partIndex` | Version / part selection |
| `protocol` | `hls` (common on iOS) |
| `directPlay` | 0/1 |
| `directStream` | 0/1 |
| `directStreamAudio` | 0/1 |
| `session` | Unique opaque session id |
| `offset` | Start ms |
| `maxVideoBitrate` | Cap |
| `videoResolution` | e.g. `1920x1080` |
| `videoQuality` | 0–100 style quality hint |
| `subtitles` | `auto` / `burn` / … |
| `subtitleSize` | UI scale |
| `audioBoost` | |
| `location` | `lan` / `wan` |
| `copyts` | Timestamp handling |
| `fastSeek` | |

Always include full client identification headers so the server can apply the correct profile.

### 4.3 Decision Endpoint

Call `/decision` first when the outcome is uncertain; inspect returned decision codes and selected stream actions (`copy` / `transcode` / `burn` / …).

## 5. Audio & Subtitle Selection

### 5.1 Audio

Priority:

1. User explicit choice (persisted preference or in-session selection)
2. Plex “selected” / default stream
3. Language preference list
4. First usable stream

Expose to UI: language, codec, channels, bitrate, default/forced flags.

### 5.2 Subtitles

Modes:

- Off
- Auto (respect forced / default + user language prefs)
- Explicit track

Rendering paths:

1. **Native** — AVPlayer text / legible media characteristics (WebVTT, some SRT, etc.)
2. **Side-loaded** — external subtitle URL fetched and attached as `AVMediaSelection` or custom overlay
3. **Burn-in** — request server transcode with subtitle burned into video

PGS / advanced ASS often force burn-in on iOS.

## 6. Playback Session Lifecycle

```
prepare(item, options)
  → decide mode
  → create AVPlayerItem / asset
  → configure AVAudioSession
  → attach observers (time, status, error)
  → report timeline (playing)
  → play()

on pause / seek / progress tick
  → local state update
  → throttled timeline POST

on stop / finish / error
  → final timeline (stopped)
  → teardown transcoder session if any
  → release player resources
```

### Timeline Reporting Rules

- On every state transition (`playing`, `paused`, `buffering`, `stopped`)
- Periodic while playing (~10 s LAN, ~20 s cellular)
- Include `time`, `duration`, `ratingKey`, `state`
- Do **not** spam on every `addPeriodicTimeObserver` tick

### Watch State

- Resume position comes from metadata (`viewOffset`) and/or timeline
- “Watched” threshold is server-configurable (default ~90 % or credits marker)
- Client can force scrobble / unscrobble via dedicated endpoints

## 7. AVFoundation Integration

Required pieces:

- `AVPlayer` + `AVPlayerItem` + `AVURLAsset`
- `AVAudioSession` category `.playback`, activate/deactivate correctly
- `MPNowPlayingInfoCenter` — title, artwork, duration, elapsed
- `MPRemoteCommandCenter` — play, pause, seek, next/previous (episodes)
- Picture in Picture (`AVPictureInPictureController` or SwiftUI equivalents)
- AirPlay via system route picker (`AVRoutePickerView` / route sharing policy)
- Background audio entitlement + proper interruption handling

Player UI (SwiftUI) must not own the engine; it observes `PlaybackState` and sends intents.

## 8. Error & Recovery

| Situation | Response |
|-----------|----------|
| Asset failed to load | Surface reason; offer quality fallback / transcode retry |
| Mid-stream network loss | Pause, attempt connection re-resolve, resume if possible |
| 401 during playback | Stop, re-auth flow |
| Transcoder session died | Restart decision with same preferences |
| Unsupported after decision | Log diagnostic decision text; fail gracefully |

## 9. Testing Matrix (Must Cover)

- Direct Play success path
- Container-only Direct Stream
- Video codec force Transcode
- Audio-only Transcode / remux
- Forced subtitle burn-in
- External SRT side-load
- Resume from `viewOffset`
- LAN → Cellular transition during play
- Server unreachable mid-session
- Token expiry mid-session
- Next-episode autoplay
- PiP start / stop
- AirPlay route change

Each automated decision test should assert both the chosen mode **and** the human-readable reason.
