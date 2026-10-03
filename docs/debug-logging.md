# Debug Logging Guide

Cross-platform log areas for field debugging. **Tokens are always redacted.**

## Categories / Areas

| Area | Covers |
|------|--------|
| `decision` / `Decision` | Dual capability matrix, mode, backend, reason |
| `playback` / `Player` / `PlayerRouter` | Open path, backend selection, prepare |
| `Track` / `TrackSwitch` | Audio/subtitle in-player vs session rebuild |
| `Timeline` | PMS progress reports |
| `Exo` / `LibVLC` / `MF` | Engine-specific prepare/errors |
| `network` / `plex` | API / discovery (iOS LogRouter) |

## Where to find logs

| Platform | Location |
|----------|----------|
| **iOS** | Xcode Console (OSLog categories) + `FileLogStore` on-device log file |
| **Android TV** | `adb logcat -s PlexATV` |
| **Windows** | `%LocalAppData%\PlexWindows\logs\debug-YYYYMMDD.log` |

## Useful filters

```bash
# Android
adb logcat -s PlexATV:* | grep -E 'Decision|Player|Track|Exo|Timeline'

# Windows (PowerShell)
Get-Content $env:LOCALAPPDATA\PlexWindows\logs\debug-*.log -Tail 100
```

Filter for Decision lines to verify system-first vs VLC fallback:
`decide system-ok` / `vlc-fallback` / `use system` / `keep system transcode`.
