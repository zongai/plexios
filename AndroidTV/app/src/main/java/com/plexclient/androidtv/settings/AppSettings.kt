package com.plexclient.androidtv.settings

import android.content.Context

/**
 * Unified settings contract aligned with iOS PlaybackSettings / SettingsTabView.
 * Token is never stored here.
 */
class AppSettings(context: Context) {
    private val prefs = context.getSharedPreferences("plex_settings", Context.MODE_PRIVATE)

    var autoPlayNextEpisode: Boolean
        get() = prefs.getBoolean(KEY_AUTO_NEXT, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_NEXT, value).apply()

    var subtitlesEnabled: Boolean
        get() = prefs.getBoolean(KEY_SUBS_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_SUBS_ENABLED, value).apply()

    var preferredAudioLanguage: String?
        get() = prefs.getString(KEY_AUDIO_LANG, null)
        set(value) = prefs.edit().putString(KEY_AUDIO_LANG, value).apply()

    var preferredSubtitleLanguage: String?
        get() = prefs.getString(KEY_SUB_LANG, null)
        set(value) = prefs.edit().putString(KEY_SUB_LANG, value).apply()

    /** bits per second — iOS max quality presets map here */
    var maxRemoteBitrate: Int
        get() = prefs.getInt(KEY_MAX_BITRATE, 20_000_000)
        set(value) = prefs.edit().putInt(KEY_MAX_BITRATE, value).apply()

    var showContinueWatching: Boolean
        get() = prefs.getBoolean(KEY_SHOW_CONTINUE, true)
        set(value) = prefs.edit().putBoolean(KEY_SHOW_CONTINUE, value).apply()

    var showRecentlyPlayed: Boolean
        get() = prefs.getBoolean(KEY_SHOW_PLAYED, true)
        set(value) = prefs.edit().putBoolean(KEY_SHOW_PLAYED, value).apply()

    var maxItemsPerHub: Int
        get() = prefs.getInt(KEY_MAX_HUB_ITEMS, 20)
        set(value) = prefs.edit().putInt(KEY_MAX_HUB_ITEMS, value).apply()

    var disabledLibraryKeys: Set<String>
        get() = prefs.getStringSet(KEY_DISABLED_LIBS, emptySet()) ?: emptySet()
        set(value) = prefs.edit().putStringSet(KEY_DISABLED_LIBS, value).apply()

    fun homeDisplay(): HomeDisplayPreferences = HomeDisplayPreferences(
        disabledLibraryKeys = disabledLibraryKeys,
        showContinueWatching = showContinueWatching,
        showRecentlyPlayed = showRecentlyPlayed,
        maxItemsPerHub = maxItemsPerHub
    )


    companion object {
        private const val KEY_AUTO_NEXT = "autoPlayNextEpisode"
        private const val KEY_SUBS_ENABLED = "subtitlesEnabled"
        private const val KEY_AUDIO_LANG = "preferredAudioLanguage"
        private const val KEY_SUB_LANG = "preferredSubtitleLanguage"
        private const val KEY_MAX_BITRATE = "maxRemoteBitrate"
        private const val KEY_SHOW_CONTINUE = "showContinueWatching"
        private const val KEY_SHOW_PLAYED = "showRecentlyPlayed"
        private const val KEY_MAX_HUB_ITEMS = "maxItemsPerHub"
        private const val KEY_DISABLED_LIBS = "disabledLibraryKeys"

        /** iOS-aligned quality labels → bps (0 = Original / high cap) */
        val QualityPresets: List<Pair<String, Int>> = listOf(
            "Original" to 100_000_000,
            "20 Mbps" to 20_000_000,
            "12 Mbps" to 12_000_000,
            "8 Mbps" to 8_000_000,
            "4 Mbps" to 4_000_000,
            "2 Mbps" to 2_000_000
        )
    }
}
