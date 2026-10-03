package com.plexclient.androidtv.settings

import com.plexclient.androidtv.plex.model.PlexHub
import com.plexclient.androidtv.plex.model.PlexLibrary
import com.plexclient.androidtv.plex.model.PlexMetadata

/** Aligned with iOS HomeDisplayPreferences. */
data class HomeDisplayPreferences(
    val disabledLibraryKeys: Set<String> = emptySet(),
    val showContinueWatching: Boolean = true,
    val showRecentlyPlayed: Boolean = true,
    val maxItemsPerHub: Int = 20
) {
    fun isLibraryEnabled(key: String) = key !in disabledLibraryKeys

    fun filter(hubs: List<PlexHub>, libraries: List<PlexLibrary>): List<PlexHub> {
        val continueItems = mutableListOf<PlexMetadata>()
        var continueTemplate: PlexHub? = null
        val playedItems = mutableListOf<PlexMetadata>()
        var playedTemplate: PlexHub? = null
        val other = mutableListOf<PlexHub>()

        for (hub in hubs) {
            when (classify(hub)) {
                PersonalKind.ContinueWatching -> {
                    if (!showContinueWatching) continue
                    if (continueTemplate == null) continueTemplate = hub
                    continueItems += hub.items
                }
                PersonalKind.RecentlyPlayed -> {
                    if (!showRecentlyPlayed) continue
                    if (playedTemplate == null) playedTemplate = hub
                    playedItems += hub.items
                }
                else -> other += hub
            }
        }

        val result = mutableListOf<PlexHub>()
        continueTemplate?.let { t ->
            val items = dedupe(continueItems, maxItemsPerHub)
            if (items.isNotEmpty()) result += t.copy(items = items)
        }
        for (hub in other) {
            val matched = libraries.firstOrNull { hub.title.contains(it.title, ignoreCase = true) }
            if (matched != null && !isLibraryEnabled(matched.key)) continue
            val items = dedupe(hub.items, maxItemsPerHub)
            if (items.isEmpty()) continue
            result += hub.copy(items = items)
        }
        playedTemplate?.let { t ->
            val items = dedupe(playedItems, maxItemsPerHub)
            if (items.isNotEmpty()) result += t.copy(items = items)
        }
        return result
    }

    private enum class PersonalKind { ContinueWatching, RecentlyAdded, RecentlyPlayed, None }

    private fun classify(hub: PlexHub): PersonalKind {
        val blob = ((hub.hubKey ?: "") + " " + hub.title).lowercase()
        return when {
            "continue" in blob || "on.deck" in blob || "ondeck" in blob ||
                "inprogress" in blob || "in progress" in blob -> PersonalKind.ContinueWatching
            "recently.added" in blob || "recently added" in blob ||
                "recentlyadded" in blob || "newest" in blob -> PersonalKind.RecentlyAdded
            "recently.played" in blob || "recently.viewed" in blob ||
                "recently played" in blob || "recently viewed" in blob ||
                "watch.again" in blob -> PersonalKind.RecentlyPlayed
            else -> PersonalKind.None
        }
    }

    private fun dedupe(items: List<PlexMetadata>, max: Int): List<PlexMetadata> {
        val seen = mutableSetOf<String>()
        val out = mutableListOf<PlexMetadata>()
        for (item in items) {
            if (!seen.add(item.ratingKey)) continue
            out += item
            if (out.size >= max) break
        }
        return out
    }
}
