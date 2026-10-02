# Plex Windows Native

Native **WinUI 3** Plex Media Server client for Windows 10/11.

Part of the multi-platform Plex client family (iOS · Android TV · Windows).  
Shared contracts: see `PlexiOS/docs/multi-platform-contracts.md`.

## Requirements

- Windows 10 1809+ / Windows 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download)
- [Windows App SDK](https://learn.microsoft.com/windows/apps/windows-app-sdk/) (restored via NuGet)
- Visual Studio 2022 17.8+ with **WinUI** workload (recommended)  
  or command-line only:

```powershell
dotnet restore
dotnet build -c Debug -p:Platform=x64
dotnet run --project src\PlexWindows\PlexWindows.csproj -p:Platform=x64
```

## Features (Phase 3 progress)

| Area | Status |
|------|--------|
| PIN authentication | ✅ (DPAPI secure storage) |
| Server discovery + ranking | ✅ |
| Sidebar shell (Fluent) | ✅ |
| Home hubs | ✅ (click → Detail) |
| Libraries (Movies / TV / Music) | ✅ |
| Metadata detail + children | ✅ |
| Search | ✅ |
| Playback decision engine | ✅ (port of iOS semantics) |
| Playback URL builder | ✅ Direct Play / Stream / Transcode |
| Player page + controls | ✅ Space / J L / ↑↓ volume / M mute / Esc |
| Next-episode autoplay | ✅ |
| Favorites (rate) | ✅ |
| Media Foundation backend | ✅ MediaPlayer + MediaPlayerElement + buffer events |
| Audio / Subtitle track UI | ✅ from Plex streams |
| Volume / Mute / auto-hide chrome | ✅ |
| Timeline report to PMS | ✅ rate-limited `:/timeline` |
| Collections page | ✅ global + per-section fallback |
| Playlists page | ✅ list + items |
| Poster image binding | ✅ PosterImageLoader on Home/Libraries/Search/Detail/Collections/Playlists |
| LibVLC fallback | ✅ packages enabled; MF→VLC router; dual surface |
| MSIX packaging | ✅ Release config + `scripts/pack-msix.ps1` |

## Architecture

```
PlexWindows/
├── Models/           # Domain models (match iOS PlexModels)
├── Plex/
│   ├── Api/          # PlexApiClient
│   ├── Auth/         # AuthenticationService + SecureStorage
│   └── Server/       # ConnectionManager
├── Playback/         # Decision engine + IPlayerEngine
├── ViewModels/       # MVVM (CommunityToolkit.Mvvm)
├── Views/            # WinUI pages
└── Helpers/          # ClientIdentity, SecureStorage
```

**UI is native WinUI 3** — not a WebView wrapper.  
**Token** is stored only via DPAPI (`ProtectedData`, CurrentUser scope).

## Playback strategy

```
Plex Playback Decision
        │
        ├── Direct Play  → Media Foundation (when codecs supported)
        ├── HLS / Transcode → Media Foundation
        └── Unsupported  → LibVLC (PlayerEngineRouter fallback)
```

Decision logic lives in `PlaybackDecisionEngine` and uses `ClientCapabilities.WindowsDefault`.

## Keyboard shortcuts (planned)

| Key | Action |
|-----|--------|
| Ctrl+F | Search |
| Space | Play / Pause |
| Media keys | System media transport |
| F11 | Fullscreen |
| Esc | Exit fullscreen / back |

## Packaging

Debug: unpackaged (`WindowsPackageType=None`) for fast iteration.  
Release: set `WindowsPackageType=MSIX` (already conditioned in csproj) and produce `.msix`.

```powershell
dotnet publish src\PlexWindows\PlexWindows.csproj -c Release -p:Platform=x64
```

## Relation to iOS

Behavior (auth, discovery ranking, decision reasons, metadata shape) follows the iOS client.  
UI follows Windows Fluent patterns (sidebar, windowing, keyboard), not a port of SwiftUI.
