# MobileVLCKit integration

## Role

MobileVLCKit is the **default Direct Play** backend when:

- SPM package `VLCKitSPM` (tylerjonesio/vlckit-spm ≥ 3.6.0) is linked
- Settings: **MobileVLCKit Direct Play** = ON
- Settings: **Prefer system player** = OFF

AVPlayer remains used for HLS Direct Stream / Transcode, and whenever system player is preferred (PiP / AirPlay Video).

## Architecture

- `VLCPlaybackBackend` — `VLCMediaPlayer` lifecycle, tracks, seek, rate
- `VLCPlayerContainer` — SwiftUI `UIViewRepresentable` drawable host
- `PlaybackEngine` — routes Direct Play → VLC → (optional native) → AVPlayer
- `IOSCapabilities.vlcProfile` — expanded containers/codecs for decision engine

## Settings

| Toggle | Effect |
|--------|--------|
| MobileVLCKit Direct Play | Use VLC capability matrix + VLC player |
| Prefer system player | Force AVPlayer path |
| Native Media Engine | Experimental FFmpeg path (separate) |

## License

MobileVLCKit is LGPLv2.1+. Linked dynamically via SPM XCFramework.
