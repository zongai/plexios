# PlexiOS

Native Swift / SwiftUI Plex Media Server client for iOS.

## Requirements

- **main / released path:** iOS 17+ / Xcode 15+ / Swift 5.9
- **`feature/swiftvlc-migration`:** iOS 18+ / **Xcode 26.3+ (Swift 6.2)** for CI (MobileVLCKit). Full [SwiftVLC 1.0](https://github.com/harflabs/SwiftVLC) needs **Xcode 26.4+ / Swift 6.3** — re-enable SPM in `project.yml` then.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Generate & open

```bash
xcodegen generate
open PlexiOS.xcodeproj
```

## Features

- Plex PIN authentication (token in Keychain)
- Server discovery & connection ranking
- Home hubs, libraries, search
- Collections, playlists, favorites
- Movie / TV detail, music (artist → album → track)
- Playback: Direct Play / Stream / Transcode decision
- PiP, AirPlay, Now Playing, remote commands
- Next-episode autoplay (including cross-season)
- Adaptive iPhone / iPad layouts

## CI

Push to `main` runs **Build unsigned IPA** (`.github/workflows/build-ipa.yml`):

1. `xcodegen generate`
2. `xcodebuild` Release, `CODE_SIGNING_ALLOWED=NO`
3. Package `.ipa` and publish a GitHub Release (`build-N`)

Re-sign the IPA with your Apple team before installing on a device (or use AltStore / Sideloadly).


## Playback engines

| Backend | When used |
|---------|-----------|
| **MobileVLCKit** | Default Direct Play when linked (`allowVLCPlayer`, not `preferSystemPlayer`) — **main** |
| **SwiftVLC** | libVLC 4 Direct Play — **in progress on `feature/swiftvlc-migration`** (scaffold only until later phases) |
| **AVPlayer** | HLS / transcode, or when system player is preferred (PiP / AirPlay Video) |
| **Native (FFmpeg)** | Experimental toggle |

### License note (MobileVLCKit / SwiftVLC)

MobileVLCKit and the libVLC binary inside SwiftVLC are **LGPLv2.1+**. Linked dynamically via SPM. Source for VideoLAN components is available from [videolan.org](https://www.videolan.org/). App-specific changes to this repository remain under the project license.
