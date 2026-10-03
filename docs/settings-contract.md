# Unified Settings Contract

Cross-platform settings keys and semantics aligned with **iOS SettingsTabView**.
Each platform implements a native Settings UI; storage is platform-secure where tokens are involved.

## Information architecture (iOS baseline)

| Section | iOS | Windows | Android TV |
|---------|-----|---------|------------|
| Account & Server | status, sign out, server list, refresh | same | status, active server, sign out |
| Display / Home | hub toggles, library pins | — (future) | — (future) |
| Playback | autoplay next, quality, languages, subtitle defaults | same subset | same subset |
| Player engine | VLC / system / NME toggles | backend: auto / MF / LibVLC | Media3 fixed (noted in About) |
| Media sources | IPTV | — | — |
| Storage | clear cache | clear image cache | clear image memory cache |
| Diagnostics | logs | — | — |
| About | version | version | version + player |

## Keys

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `autoPlayNextEpisode` | bool | `true` | Player ends → next episode |
| `subtitlesEnabled` | bool | `true` | Prefer subtitles when available |
| `preferredAudioLanguage` | string? | null | ISO 639 code |
| `preferredSubtitleLanguage` | string? | null | ISO 639; null = no preference |
| `maxRemoteBitrate` | int | 20000000 | bps for Remote/Relay; quality presets map here |
| `playerBackend` | enum | `auto` | Windows only: `auto` \| `mediaFoundation` \| `libVlc` |
| `clearImageCache` | action | — | Clears poster disk/memory cache |
| `signOut` | action | — | Clears token; returns to PIN |

### Quality presets (iOS parity)

| Label | bps |
|-------|-----|
| Original | 100000000 (soft cap) |
| 20 Mbps | 20000000 |
| 12 Mbps | 12000000 |
| 8 Mbps | 8000000 |
| 4 Mbps | 4000000 |
| 2 Mbps | 2000000 |

## Storage

| Platform | Mechanism |
|----------|-----------|
| iOS | `UserDefaults` for prefs; Keychain for token |
| Android TV | `SharedPreferences` for prefs; EncryptedSharedPreferences for token |
| Windows | `%LocalAppData%\PlexWindows\settings.json`; DPAPI for token |

## UI placement

- **iOS**: Settings tab → sectioned list → detail pages
- **Android TV**: Side nav / Home → Settings (D-pad sections)
- **Windows**: NavigationView Settings item

Settings UI must never display the raw auth token.
