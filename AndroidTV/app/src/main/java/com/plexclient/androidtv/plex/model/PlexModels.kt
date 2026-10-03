package com.plexclient.androidtv.plex.model

/** Domain models aligned with iOS / Windows PlexModels (no XML in UI). */

data class PlexPin(
    val id: Int,
    val code: String,
    val expiresIn: Int,
    val authToken: String?
)

data class PlexConnection(
    val uri: String,
    val address: String?,
    val port: Int?,
    val protocol: String,
    val local: Boolean,
    val relay: Boolean,
    val ipv6: Boolean
) {
    /** Lower is better — mirrors iOS PlexConnection.rankScore */
    val rankScore: Int
        get() {
            var score = 0
            if (relay) score += 1000
            if (!local) score += 100
            if (local && protocol.equals("https", true)) score += 5
            if (!local && !protocol.equals("https", true)) score += 10
            if (ipv6) score += 1
            return score
        }
}

data class PlexServer(
    val name: String,
    val machineIdentifier: String,
    val accessToken: String,
    val product: String?,
    val provides: String?,
    val connections: List<PlexConnection>
)

enum class PlexLibraryType { Movie, Show, Artist, Photo, Mixed, Unknown }

data class PlexLibrary(
    val key: String,
    val title: String,
    val type: PlexLibraryType,
    val agent: String?,
    val uuid: String?
)

enum class PlexMetadataType {
    Movie, Show, Season, Episode, Artist, Album, Track, Playlist, Collection, Clip, Unknown
}

data class PlexStream(
    val id: Int,
    val streamType: StreamType,
    val codec: String?,
    val language: String?,
    val languageCode: String?,
    val title: String?,
    val displayTitle: String?,
    val extendedDisplayTitle: String?,
    val channels: Int?,
    val format: String?,
    val selected: Boolean
) {
    enum class StreamType { Video, Audio, Subtitle, Unknown }
}

data class PlexPart(
    val id: Int,
    val key: String,
    val duration: Long?,
    val file: String?,
    val container: String?,
    val streams: List<PlexStream>
)

data class PlexMedia(
    val id: Int,
    val duration: Long?,
    val bitrate: Int?,
    val width: Int?,
    val height: Int?,
    val videoCodec: String?,
    val audioCodec: String?,
    val container: String?,
    val videoProfile: String?,
    val parts: List<PlexPart>
)


enum class PlexMarkerType { Intro, Credits, Commercial, Unknown }

/** Plex intro/credits marker; offsets in milliseconds. */
data class PlexMarker(
    val id: Int,
    val type: PlexMarkerType,
    val startTimeOffset: Long,
    val endTimeOffset: Long
) {
    fun contains(positionMs: Long): Boolean =
        positionMs >= startTimeOffset && positionMs < endTimeOffset && endTimeOffset > startTimeOffset
}

data class PlexMetadata(
    val ratingKey: String,
    val key: String,
    val type: PlexMetadataType,
    val title: String,
    val summary: String?,
    val year: Int?,
    val thumb: String?,
    val art: String?,
    val parentThumb: String?,
    val grandparentThumb: String?,
    val parentTitle: String?,
    val grandparentTitle: String?,
    val parentRatingKey: String?,
    val grandparentRatingKey: String?,
    val index: Int?,
    val parentIndex: Int?,
    val duration: Long?,
    val viewOffset: Long?,
    val contentRating: String?,
    val studio: String?,
    val tagline: String?,
    val userRating: Double? = null,
    val media: List<PlexMedia>,
    val markers: List<PlexMarker> = emptyList()
) {
    val isFavorite: Boolean get() = (userRating ?: 0.0) >= 1.0
}

data class PlexHub(
    val hubKey: String?,
    val title: String,
    val type: String?,
    val items: List<PlexMetadata>
)

data class ServerContext(
    val baseUrl: java.net.URI,
    val token: String,
    val machineIdentifier: String
)
