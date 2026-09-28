# iOS Capabilities Relevant to a Plex Client

This document maps Apple platform capabilities to Plex client requirements and records known constraints that affect Direct Play / Direct Stream / Transcode decisions.

## 1. UI Framework & Architecture

| Requirement | Apple API / Pattern |
|-------------|---------------------|
| Declarative UI | SwiftUI |
| State | `@Observable` (Observation framework), `@State`, `@Environment` |
| Navigation (iPhone) | `NavigationStack` |
| Navigation (iPad) | `NavigationSplitView` + sidebar |
| Lists / grids | `List`, `LazyVStack`, `LazyVGrid`, `ScrollView` |
| Images | Custom `ImagePipeline` + `AsyncImage` only as leaf helper |
| Concurrency | `async/await`, `Task`, `TaskGroup`, `Actor`, `@MainActor` |
| Persistence | SwiftData and/or SQLite / GRDB |
| Secure storage | Keychain Services |
| Logging | `Logger` / OSLog |
| Network path | `NWPathMonitor` (Network.framework) |

Follow AvdLee SwiftUI-Agent-Skill guidance: unidirectional data flow, localized state, avoid `AnyView`, avoid giant views, cancel tasks on disappear.

## 2. Media Playback Stack

| Need | API |
|------|-----|
| Core player | `AVPlayer`, `AVPlayerItem`, `AVURLAsset` |
| UI kit integration | AVKit (`VideoPlayer`, player view controllers as needed) |
| Audio session | `AVAudioSession` (`.playback`, AirPlay, PiP) |
| Now Playing | `MPNowPlayingInfoCenter` |
| Remote commands | `MPRemoteCommandCenter` |
| Picture in Picture | `AVPictureInPictureController` / SwiftUI PiP support |
| AirPlay | System route sharing + `AVRoutePickerView` |
| Legible media (subs) | `AVMediaSelectionGroup` / characteristics; custom overlay when needed |
| Background playback | Audio background mode entitlement |

### Capability Caveats (decision engine must encode these)

- **Containers**: MP4 / M4V / MOV generally safest; MKV often requires Direct Stream or Transcode depending on OS version and contents.
- **Video codecs**: H.264 broadly supported; HEVC widely supported on recent devices; AV1 support is device/OS dependent; advanced HDR / Dolby Vision profiles vary by SoC generation.
- **Audio**: AAC, MP3 reliable; AC3/EAC3 common; TrueHD / DTS / Atmos support is limited and often forces transcode or passthrough constraints.
- **Subtitles**:
  - Text (SRT, VTT) — often side-loadable
  - Image-based (PGS) — typically burn-in
  - Complex ASS/SSA — frequently burn-in
- **HDR**: Tone mapping and format support differ across iPhone / iPad generations; never assume universal DV support.

Maintain a **versioned capability table** queried by the decision engine rather than scattering `#available` checks.

## 3. Networking

| Need | API |
|------|-----|
| HTTP | `URLSession` (async) |
| Path monitor | `NWPathMonitor` |
| Bonjour / local (optional) | `NWBrowser` / NetService if local discovery beyond plex.tv is desired |
| TLS | Default URLSession trust; plex.direct certificates |

Background URLSession can be used later for downloads; keep online browsing on the default session.

## 4. Security & Privacy

- Keychain for tokens (accessibility: `afterFirstUnlockThisDeviceOnly` or tighter as appropriate)
- App Transport Security: allow local network exceptions only if required; prefer HTTPS
- Local Network permission usage string if probing LAN
- No tokens in logs, analytics, or crash reports
- Face ID / Optic ID not required for basic auth; optional for settings lock later

## 5. System Integration

| Feature | Notes |
|---------|-------|
| Background audio | Required for lock-screen / Control Center continuation |
| PiP | Video multitasking; respect user settings |
| AirPlay | Prefer system UI; do not reimplement protocol |
| CarPlay | Out of scope for early phases |
| Widgets / Live Activities | Future enhancement for Continue Watching |
| App Intents / Siri | Future |
| Focus / Dark Mode / Dynamic Type | First-class from day one |
| Accessibility | VoiceOver labels, Reduce Motion, sufficient contrast |

## 6. Performance Budgets (Targets)

- Home hub first meaningful paint: < 500 ms after cache hit; < 2 s cold network
- Library grid scroll: 60 fps on recent devices with image downsampling
- Playback start (Direct Play, LAN): < 1 s to first frame when possible
- Memory: aggressive image cache limits; purge on memory warnings
- Avoid main-thread JSON/XML decode and image decode

Instruments: Time Profiler, Allocations, SwiftUI instrument, Network.

## 7. Device Classes

| Class | Layout bias |
|-------|-------------|
| iPhone | Tab + NavigationStack, compact cards |
| iPad | NavigationSplitView, multi-column, larger hero art |
| Mac (Catalyst / designed for iPad) | Optional later; do not block phone/pad |

Use size classes and `NavigationSplitView` visibility rather than duplicated view hierarchies.

## 8. Entitlements & Capabilities Checklist

- [ ] Background Modes → Audio
- [ ] (Optional) Background Modes → Background fetch / processing for future refresh
- [ ] Keychain sharing (only if needed across extensions)
- [ ] App Sandbox (Mac) if applicable
- [ ] Local Network usage description
- [ ] Photo Library (only if user-selected artwork export later)

## 9. Testing on Device vs Simulator

- Simulator lacks full hardware decode / HDR / some AirPlay paths
- Always validate playback decision matrix on physical devices spanning:
  - Older A-series (baseline HEVC)
  - Recent Pro devices (advanced HDR)
  - Cellular constrained networks

## 10. Mapping to Project Components

| iOS capability | Project owner |
|----------------|---------------|
| SwiftUI + Observation | Features / UI |
| URLSession + Network | Core/Networking + ConnectionManager |
| Keychain | Authentication |
| AVFoundation / AVKit | PlaybackEngine |
| MPNowPlaying / Remote | PlaybackEngine + Player feature |
| NWPathMonitor | ConnectionManager |
| SwiftData / SQLite | Core/Persistence |
| OSLog | Core/Logging |
| Image caching | ImagePipeline |
