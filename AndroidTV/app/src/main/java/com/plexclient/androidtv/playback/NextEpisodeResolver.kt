package com.plexclient.androidtv.playback

import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.model.PlexMetadataType
import com.plexclient.androidtv.plex.model.ServerContext

/**
 * Resolves the next episode after [current], including cross-season.
 * Mirrors iOS / Windows NextEpisodeResolver semantics.
 */
object NextEpisodeResolver {
    suspend fun findNext(
        api: PlexApiClient,
        context: ServerContext,
        current: PlexMetadata
    ): PlexMetadata? {
        if (current.type != PlexMetadataType.Episode) return null
        val seasonKey = current.parentRatingKey ?: return null
        val showKey = current.grandparentRatingKey

        val siblings = api.fetchChildren(seasonKey, context.baseUrl, context.token)
            .filter { it.type == PlexMetadataType.Episode }
            .sortedBy { it.index ?: 0 }

        val idx = siblings.indexOfFirst { it.ratingKey == current.ratingKey }
        if (idx >= 0 && idx + 1 < siblings.size) {
            return api.fetchMetadata(siblings[idx + 1].ratingKey, context.baseUrl, context.token)
        }

        // Cross-season: next season's first episode
        if (showKey.isNullOrBlank()) return null
        val seasons = api.fetchChildren(showKey, context.baseUrl, context.token)
            .filter { it.type == PlexMetadataType.Season }
            .sortedBy { it.index ?: 0 }
        val seasonIdx = seasons.indexOfFirst { it.ratingKey == seasonKey }
        if (seasonIdx < 0 || seasonIdx + 1 >= seasons.size) return null
        val nextSeason = seasons[seasonIdx + 1]
        val episodes = api.fetchChildren(nextSeason.ratingKey, context.baseUrl, context.token)
            .filter { it.type == PlexMetadataType.Episode }
            .sortedBy { it.index ?: 0 }
        val first = episodes.firstOrNull() ?: return null
        return api.fetchMetadata(first.ratingKey, context.baseUrl, context.token)
    }
}
