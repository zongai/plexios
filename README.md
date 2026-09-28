# PlexiOS

Native Swift / SwiftUI Plex Media Server client for iOS.

## Requirements

- iOS 17+
- Xcode 15+
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
