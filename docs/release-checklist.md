# Release Checklist — Plex iOS Native Client

## Pre-release

### Functional

- [ ] PIN sign-in completes and token persists across relaunch
- [ ] Sign-out clears Keychain token and returns to SignIn
- [ ] Server discovery lists owned + shared servers
- [ ] Active server switch works when multiple servers present
- [ ] Home hubs load; empty hubs hidden
- [ ] Library list → grid → detail navigation
- [ ] Movie Play / Resume starts player
- [ ] Show → Season → Episode → Play
- [ ] Search debounce; cancel in-flight on new query
- [ ] Timeline updates appear on PMS dashboard while playing
- [ ] Resume position after partial watch
- [ ] Audio / subtitle menu changes take effect
- [ ] PiP starts and restores UI on stop
- [ ] AirPlay route picker presents devices
- [ ] Lock screen play/pause/skip/scrub works
- [ ] Phone call interruption pauses; resume when appropriate
- [ ] Headphones unplug pauses
- [ ] Offline banner appears when network is off
- [ ] Cached library/home still visible offline (within TTL)
- [ ] Image cache clear in Settings frees disk

### Device matrix

- [ ] iPhone (compact) — TabView
- [ ] iPad (regular) — Sidebar NavigationSplitView
- [ ] Light Mode / Dark Mode
- [ ] Dynamic Type largest accessibility size (no clipping on critical screens)
- [ ] VoiceOver: Sign-in PIN, poster card, Play button

### Performance (Instruments)

- [ ] Home cold load < target in `ios-capabilities.md` (or documented exception)
- [ ] Scrolling library grid — no main-thread image decode spikes
- [ ] Memory: no unbounded growth after open/close 20 titles
- [ ] Playback start to first frame acceptable on LAN

### Security

- [ ] Token only in Keychain (not UserDefaults / logs)
- [ ] Logs redact `X-Plex-Token` and query tokens
- [ ] No secrets in source or Info.plist

### Xcode / packaging

- [ ] Background Modes: Audio, AirPlay, PiP
- [ ] `NSLocalNetworkUsageDescription` present
- [ ] Deployment target iOS 17+
- [ ] Release build succeeds (no force-cast / TODO blockers)
- [ ] App icon & display name set
- [ ] Privacy Nutrition Labels drafted (network, local network)

## Known limitations (document in release notes)

- Next-episode autoplay not fully wired
- Subtitle side-load rendering limited to native formats; others burn-in via transcode
- AV1 / Dolby Vision support is conservative (capability matrix)
- Downloads (offline files) not implemented
- Live TV / DVR not in scope for v1

## Post-release

- [ ] Crash reporting (optional) wired
- [ ] Monitor PMS timeline accuracy from user feedback
- [ ] Track Direct Play vs Transcode ratio if telemetry added later
