# Multi-Platform Shared Contracts

Reference definitions for iOS / Android TV / Windows implementations.  
Canonical behavior is the existing iOS client.

## 1. Client Identity Headers (all requests)

```
X-Plex-Client-Identifier: <stable UUID per install>
X-Plex-Product:           Plex <Platform> Native   # e.g. "Plex iOS Native", "Plex Android TV", "Plex Windows"
X-Plex-Version:           <app version>
X-Plex-Platform:          iOS | Android | Windows
X-Plex-Platform-Version:  <OS version>
X-Plex-Device:            <device family>
X-Plex-Device-Name:       <user-visible name>
X-Plex-Device-Vendor:     Apple | Google | Microsoft
X-Plex-Token:             <token>                  # prefer header over query
```

## 2. Authentication

### Create PIN
```
POST https://clients.plex.tv/api/v2/pins
Accept: application/json
+ identity headers

→ { id, code, expiresIn, authToken: null }
```
Use non-strong PIN (short 4-character code) for classic plex.tv/link flow.

### Poll PIN
```
GET https://clients.plex.tv/api/v2/pins/{id}?code={code}
→ when claimed: authToken populated
```

### Storage rules
- Never log token
- Never write token to ordinary JSON / SharedPreferences / files
- Platform secure store only

## 3. Server Discovery

```
GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1
X-Plex-Token: <account token>
```

Filter resources where `provides` contains `server`.  
Each server carries its own `accessToken` and `connections[]`.

### Ranking (reference algorithm from iOS `PlexConnection.rankScore`)
Lower score is better:
- Relay → +1000
- Non-local → +100
- Local HTTPS → +5 (prefer local HTTP slightly because of self-signed / ATS issues)
- Remote non-HTTPS → +10
- IPv6 → +1

Then refine with measured latency and successful probe.

## 4. ClientCapabilities Interface

Each platform must supply a concrete implementation used by `PlaybackDecisionEngine`.

```
struct ClientCapabilities {
  // Containers the player can open natively
  supportedContainers: Set<String>          // "mp4", "mkv", "mov", ...

  // Video
  supportedVideoCodecs: Set<String>         // "h264", "hevc", "av1", ...
  supportedVideoProfiles: Set<String>       // optional finer grain
  maxVideoWidth: Int
  maxVideoHeight: Int
  supportsHDR10: Bool
  supportsDolbyVision: Bool
  supportsHLG: Bool

  // Audio
  supportedAudioCodecs: Set<String>         // "aac", "ac3", "eac3", "truehd", "dts", ...
  maxAudioChannels: Int

  // Subtitles
  supportedSubtitleFormats: Set<String>     // "srt", "ass", "vtt", "pgs", ...
  canRenderTextSubtitles: Bool
  canRenderBitmapSubtitles: Bool
  requiresBurnInFor: Set<String>            // formats that force burn-in

  // Delivery
  supportsDirectPlay: Bool
  supportsDirectStream: Bool
  supportsTranscode: Bool
  supportsHLS: Bool
  supportsDASH: Bool

  // Platform extras (flags only; decision engine may ignore)
  supportsPiP: Bool
  supportsAirPlay: Bool
  supportsBackgroundPlayback: Bool
  supportsRemoteCommandCenter: Bool
}
```

iOS reference: `IOSCapabilities` + `PlaybackPreferences`.

## 5. PlaybackDecision

```
enum PlaybackMode { directPlay, directStream, transcode }

struct PlaybackDecision {
  mode: PlaybackMode
  reason: String                    // human-readable, for diagnostics & tests
  mediaIndex: Int
  partIndex: Int
  selectedAudioStreamId: Int?
  selectedSubtitleStreamId: Int?    // null = off
  burnInSubtitles: Bool
  maxBitrateKbps: Int?
}
```

Decision priority: Direct Play → Direct Stream → Transcode.

When client cannot handle a stream natively, prefer asking the PMS to transcode rather than implementing a full software decoder on every platform.

## 6. Playback Session State Machine

```
START
  ↓
PLAYING  ←→  PAUSED
  ↓
STOP / COMPLETED
```

Periodic progress reports (rate-limited) while PLAYING.  
Reporting failure must not stop local playback; retry with backoff when network returns.

## 7. Next Episode Resolution

1. If current item is Episode and has next in same season → that episode
2. Else if next season exists → first episode of next season
3. Respect specials / missing episodes / playlist order / watched state according to existing iOS behavior

## 8. Player Abstraction (per platform)

```
interface PlayerEngine {
  prepare(request)
  play()
  pause()
  stop()
  seek(positionMs)
  setVolume(level)
  selectAudioTrack(id)
  selectSubtitle(id | null)
  currentTime / duration / buffered / state
}
```

Platform implementations:
- iOS: routes to VLC / AVPlayer / Native Media Engine
- Android TV: Media3 ExoPlayer (+ optional FFmpeg extension later)
- Windows: Media Foundation primary, LibVLC or FFmpeg fallback

## 9. Error Model (shared semantics)

```
AuthenticationExpired
ServerUnavailable
ConnectionChanged
NetworkOffline
PlaybackUnsupported
TranscodeFailed
...
```

UI layers map these to localized recovery actions; core must not depend on UI strings.

## 10. Image Caching Policy

- Memory + Disk tiers
- Keys derived from Plex image URLs (thumb / art / episode stills)
- Platform-native cache implementations (do not share binary caches across platforms)

---

These contracts are intentionally language-neutral.  
iOS already implements them. Android TV and Windows must match behavior, not source code.
