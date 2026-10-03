# Plex Android TV

Native **Kotlin + Jetpack Compose for TV** client for Android TV / Google TV.

Part of the multi-platform Plex client family (iOS · Android TV · Windows).  
Shared contracts: `PlexiOS/docs/multi-platform-contracts.md`.

## Requirements

- Android Studio Ladybug+ or command-line Android SDK
- JDK 17
- Android TV / Google TV device or emulator (API 26+)

```bash
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Status (Phase 5–7)

| Area | Status |
|------|--------|
| PIN auth (`plex.tv/link`) | ✅ EncryptedSharedPreferences |
| Server discovery + rank/probe | ✅ |
| Home hubs + posters (Coil) | ✅ |
| Libraries grid + posters | ✅ |
| Detail (children / related / play / favorite) | ✅ |
| Search (debounced) | ✅ |
| Collections (global + section fallback) | ✅ |
| Playlists | ✅ |
| PlaybackDecisionEngine | ✅ Media3 capability matrix |
| PlaybackUrlBuilder | ✅ DP / DS / Transcode |
| Media3 / ExoPlayer | ✅ PlayerView |
| Next-episode autoplay | ✅ cross-season |
| Timeline report to PMS | ✅ rate-limited |
| Poster Coil loading | ✅ `PlexImage` + `PosterCard` |
| Audio / subtitle tracks | ✅ Media3 track panel |
| Release APK arm64-v8a | ✅ `assembleRelease` + CI |

## Architecture

```
app/src/main/java/com/plexclient/androidtv/
├── di/AppContainer.kt
├── plex/
│   ├── identity/ · auth/ · api/ · server/
│   ├── image/PlexImage
│   └── model/PlexModels
├── playback/
│   ├── PlaybackDecisionEngine · PlaybackUrlBuilder
│   ├── Media3PlayerShell · NextEpisodeResolver · TimelineReporter
└── ui/
    ├── components/PosterCard
    ├── signIn · home · libraries · detail
    ├── search · collections · playlists · player
```

## Flow

```
SignIn → Discover servers → Home
  ├─ Libraries → Detail → Play
  ├─ Search → Detail → Play
  ├─ Collections → children → Detail → Play
  └─ Playlists → items → Detail → Play

Player: Media3 · next episode · timeline
```

## Notes

- Cleartext + trust-all SSL is intentional for local PMS self-signed certs.
- Show/Season open Detail for drill-down; only Movie/Episode/Track start Player.
