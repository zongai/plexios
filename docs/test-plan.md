# Test Plan — Plex iOS Native Client

## Unit tests (XCTest)

| Suite | Coverage |
|-------|----------|
| `PlaybackDecisionTests` | Direct Play / Stream / Transcode, bitrate cap, PGS burn-in, non-empty reasons |
| `PlaybackURLBuilderTests` | Direct Play URL, HLS transcode params, session/offset |
| `ErrorMappingTests` | Offline, timeout, 401/503, cancellation, recovery suggestions |
| `MediaModelTests` | Progress, watched, connection rank, card subtitles |
| `ResponseCacheTests` | Store/retrieve, TTL expiry |
| `PlexAPIMapperTests` | Library, connection rank, metadata mapping |
| `AuthenticationStateTests` | Auth state machine |
| `HTTPClientTests` / `KeychainStoreTests` / `LogRedactionTests` | Infrastructure |

Run in Xcode: **Product → Test** (⌘U).

## Integration (manual / future UI tests)

1. **Auth**: Start PIN → authorize on plex.tv/link → app becomes signed-in
2. **Discovery**: At least one server appears; preferred connection is local when on LAN
3. **Browse**: Open Movies library, open detail, back-navigate
4. **Playback**: Play → scrub → pause → resume → stop; verify PMS Now Playing
5. **Offline**: Enable Airplane Mode → offline banner; open previously cached home
6. **PiP**: Start playback → background → PiP continues
7. **iPad**: Sidebar switches sections; detail updates

## Error injection ideas

- Invalid token → 401 → forced re-auth messaging
- Kill PMS mid-playback → player error state + recovery copy
- Slow network (Network Link Conditioner) → buffering indicator + timeline still throttled

## Regression priorities before each release

1. Sign-in / Keychain restore  
2. Playback decision + timeline  
3. Image pipeline memory warning path  
4. Adaptive navigation (phone vs iPad)  
