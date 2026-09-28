# Info.plist / Capabilities (Phase 5)

Add these in Xcode target settings:

## Background Modes

- **Audio, AirPlay, and Picture in Picture**  
  Required for lock-screen continuation, AirPlay, and PiP.

## Optional usage strings

```
NSLocalNetworkUsageDescription
  Plex iOS discovers and connects to your Plex Media Server on the local network.

NSBonjourServices (if using GDM later)
  _plexmediaserver._tcp
```

## Scene / lifecycle

No special UIBackgroundModes beyond audio are required for basic playback.
PiP is enabled via `AVPlayerViewController.allowsPictureInPicturePlayback`.

## Entitlements checklist

- [x] Background Modes → Audio
- [x] Background Modes → Picture in Picture (grouped with Audio on modern Xcode)
- [ ] App Groups (only if sharing with extensions later)
