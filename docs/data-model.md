# Data Model

Three model layers keep concerns separated:

1. **API DTOs** — exact shapes returned by PMS / plex.tv (Decodable)
2. **Domain models** — app-centric, stable, UI- and engine-friendly
3. **Persistence models** — SwiftData / SQLite entities for cache & offline readiness

Never let API DTOs become the app-wide state type.

## 1. Core Domain Entities

### PlexUser

- id, uuid, username, email, friendlyName
- home / restricted flags
- thumb URL
- auth token reference (never stored on the model itself in memory dumps)

### PlexServer

- machineIdentifier (primary identity)
- name, product, productVersion, platform
- owned / home flags
- accessToken (secure reference)
- connections: [PlexConnection]
- preferredConnection (resolved)

### PlexConnection

- uri, address, port, protocol
- local, relay, ipv6
- latency / lastSuccess (runtime)

### PlexLibrary (Section)

- key / id, uuid
- title, type (movie, show, artist, photo, …)
- agent, scanner
- art / composite / thumb
- count / updatedAt

### PlexHub

- key, title, type, hubIdentifier
- style (hero, shelf, …)
- items: [PlexMetadata] (or lightweight cards)
- size / more link

### PlexMetadata (base)

Common fields for movie / show / season / episode / collection / …

- ratingKey, key, guid, type, subtype
- title, titleSort, originalTitle
- summary, year, originallyAvailableAt
- contentRating, rating, audienceRating
- duration (ms)
- viewCount, viewOffset, lastViewedAt
- thumb, art, parentThumb, grandparentThumb, …
- genres, directors, writers, roles (actors)
- studio, tagline
- Media: [PlexMedia]
- children / leafCount / childCount (hierarchy)

### Specialized Metadata

| Type | Extra fields |
|------|--------------|
| **PlexMovie** | editionTitle, chapterSource, … |
| **PlexShow** | leafCount, viewedLeafCount, seasonCount, childCount |
| **PlexSeason** | seasonNumber, parentRatingKey, leafCount |
| **PlexEpisode** | episodeNumber, seasonNumber, parent / grandparent titles & keys, air date |
| **PlexCollection** | collection type subtype, childCount |
| **PlexPlaylist** | playlistType, duration, leafCount, smart |

### PlexMedia

- id, duration, bitrate, width, height
- videoCodec, audioCodec, container
- videoResolution, videoFrameRate, videoProfile
- audioChannels, audioProfile
- Part: [PlexPart]

### PlexPart

- id, key, duration, size, container, file
- accessible, exists, optimizedForStreaming
- Stream: [PlexStream]

### PlexStream

- id, streamType (1=video, 2=audio, 3=subtitle)
- codec, format, language, languageCode, languageTag
- displayTitle, extendedDisplayTitle, title
- default, forced, selected, external
- bitrate, channels, samplingRate, bitDepth, …
- key (for external subs)
- HDR / color metadata when present

### PlexImage

- type (thumb, art, poster, clearLogo, …)
- url / path
- width, height (when known)

### PlexSession (Playback)

- sessionId
- ratingKey, mediaIndex, partIndex
- state (playing, paused, buffering, stopped)
- position, duration
- playDecision (directPlay / directStream / transcode)
- selectedAudioStreamId, selectedSubtitleStreamId
- qualityProfile / maxBitrate

## 2. Mapping Rules

```
API DTO  --map-->  Domain Model  --optional-->  Persistence Model
```

- Mapping is pure and testable
- Domain models use Swift value types (`struct`) where practical
- Identifiers: prefer `ratingKey` + server machineIdentifier as composite identity when needed
- Dates: parse ISO / Plex formats into `Date`
- Durations: store milliseconds as `Int64` or `Duration`

## 3. Persistence Strategy

### What to cache

| Data | Memory | Disk | Notes |
|------|--------|------|-------|
| Active server list | ✓ | ✓ | Fast cold start |
| Library sections | ✓ | ✓ | |
| Hub shelves (Home) | ✓ | short TTL | |
| Metadata detail | ✓ | medium TTL | Invalidate on watch state change |
| Images | ✓ | ✓ | ImagePipeline owned |
| Playback progress (local) | ✓ | ✓ | Until confirmed by server |
| Search recent queries | ✓ | ✓ | |

### Invalidation

- Explicit: user pull-to-refresh, mark played, server switch
- TTL: hubs short, library lists medium, static art long
- Event-driven: timeline response, websocket/activity if later adopted

### Offline readiness (future)

Reserve:

- Full metadata snapshot tables
- Downloaded media file references
- Artwork files on disk

Do not complicate online path for offline in early phases.

## 4. Identity & Equality

- `PlexServer`: `machineIdentifier`
- `PlexLibrary`: server + section key/uuid
- `PlexMetadata`: server + ratingKey
- Streams / Parts: id within parent Media

SwiftUI `ForEach` must use stable identity (ratingKey or composite), never array index.

## 5. Image References

Store relative or absolute paths from metadata; resolve to full URL via:

```
{serverBase}{path}?X-Plex-Token=...
```

or photo transcoder with width/height. Domain layer should expose ready-to-fetch `URL` values after connection resolution.

## 6. Watch State Fields

| Field | Meaning |
|-------|---------|
| `viewOffset` | Resume position (ms) |
| `viewCount` | Times completed / scrobbled |
| `lastViewedAt` | Last interaction |
| `fullyAvailable` / leaves viewed | Show progress aggregation |

UI derives “In Progress”, “Watched”, “Unwatched” badges from these + duration thresholds.

## 7. Anti-Patterns

- Using `[String: Any]` or raw XML trees in ViewModels
- Encoding tokens into domain model `Codable` representations that get logged
- Mixing API field names (`ratingKey` vs `id`) inconsistently across layers
- Giant “god” model that contains entire library graph in memory
