package com.plexclient.androidtv.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.ui.Modifier
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.plexclient.androidtv.plex.auth.AuthRepository
import com.plexclient.androidtv.plex.server.ConnectionManager
import com.plexclient.androidtv.settings.AppSettings
import com.plexclient.androidtv.ui.components.TvNavChip
import com.plexclient.androidtv.ui.components.TvPage

/**
 * Settings layout aligned with iOS SettingsTabView:
 * Account & Server · Playback · Storage · About
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SettingsScreen(
    settings: AppSettings,
    auth: AuthRepository,
    connections: ConnectionManager,
    onBack: () -> Unit,
    onSignedOut: () -> Unit
) {
    var autoNext by remember { mutableStateOf(settings.autoPlayNextEpisode) }
    var subsEnabled by remember { mutableStateOf(settings.subtitlesEnabled) }
    var status by remember { mutableStateOf("") }
    var showContinue by remember { mutableStateOf(settings.showContinueWatching) }
    var showPlayed by remember { mutableStateOf(settings.showRecentlyPlayed) }
    var maxItems by remember { mutableStateOf(settings.maxItemsPerHub) }
    var qualityLabel by remember {
        mutableStateOf(
            AppSettings.QualityPresets.firstOrNull { it.second == settings.maxRemoteBitrate }?.first
                ?: "20 Mbps"
        )
    }

    TvPage(title = "Settings", onBack = onBack) {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { SectionTitle("Account & Server") }
            item {
                Text(
                    text = if (auth.isSignedIn) "Status: Signed in" else "Status: Signed out",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
            item {
                val serverName = connections.activeServer?.name
                Text(
                    text = if (serverName != null) "Server: $serverName" else "Server: —",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            item {
                TvNavChip(
                    label = "Sign out",
                    onClick = {
                        auth.signOut()
                        status = "Signed out"
                        onSignedOut()
                    }
                )
            }

            
            item { SectionTitle("Home") }
            item {
                TvNavChip(
                    label = "Continue Watching: ${if (showContinue) "On" else "Off"}",
                    onClick = {
                        showContinue = !showContinue
                        settings.showContinueWatching = showContinue
                        status = "Continue Watching: ${if (showContinue) "On" else "Off"}"
                    }
                )
            }
            item {
                TvNavChip(
                    label = "Recently Played: ${if (showPlayed) "On" else "Off"}",
                    onClick = {
                        showPlayed = !showPlayed
                        settings.showRecentlyPlayed = showPlayed
                        status = "Recently Played: ${if (showPlayed) "On" else "Off"}"
                    }
                )
            }
            item {
                Text(
                    text = "Max items per row: $maxItems",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            items(listOf(10, 15, 20, 30, 50).size) { index ->
                val n = listOf(10, 15, 20, 30, 50)[index]
                TvNavChip(
                    label = "$n",
                    onClick = {
                        maxItems = n
                        settings.maxItemsPerHub = n
                        status = "Max items: $n"
                    }
                )
            }

item { SectionTitle("Playback") }
            item {
                TvNavChip(
                    label = "Auto-play next episode: ${if (autoNext) "On" else "Off"}",
                    onClick = {
                        autoNext = !autoNext
                        settings.autoPlayNextEpisode = autoNext
                        status = "Auto-play next: ${if (autoNext) "On" else "Off"}"
                    }
                )
            }
            item {
                TvNavChip(
                    label = "Subtitles default: ${if (subsEnabled) "On" else "Off"}",
                    onClick = {
                        subsEnabled = !subsEnabled
                        settings.subtitlesEnabled = subsEnabled
                        status = "Subtitles default: ${if (subsEnabled) "On" else "Off"}"
                    }
                )
            }
            item {
                Text(
                    text = "Max remote quality: $qualityLabel",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            items(AppSettings.QualityPresets.size) { index ->
                val (label, bps) = AppSettings.QualityPresets[index]
                TvNavChip(
                    label = label,
                    onClick = {
                        settings.maxRemoteBitrate = bps
                        qualityLabel = label
                        status = "Quality: $label"
                    }
                )
            }

            
            item {
                Text(
                    text = "Audio: ${settings.preferredAudioLanguage ?: "Auto"} · Sub: ${settings.preferredSubtitleLanguage ?: "Auto"}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            item {
                Text(text = "Audio language", style = MaterialTheme.typography.labelLarge)
            }
            items(listOf("" to "Auto", "en" to "English", "zh" to "Chinese", "ja" to "Japanese", "ko" to "Korean", "es" to "Spanish", "fr" to "French", "de" to "German").size) { i ->
                val (code, label) = listOf("" to "Auto", "en" to "English", "zh" to "Chinese", "ja" to "Japanese", "ko" to "Korean", "es" to "Spanish", "fr" to "French", "de" to "German")[i]
                TvNavChip(
                    label = label,
                    onClick = {
                        settings.preferredAudioLanguage = code.ifEmpty { null }
                        status = "Audio language: $label"
                    }
                )
            }
            item {
                Text(text = "Subtitle language", style = MaterialTheme.typography.labelLarge)
            }
            items(listOf("" to "Auto", "en" to "English", "zh" to "Chinese", "ja" to "Japanese", "ko" to "Korean", "es" to "Spanish", "fr" to "French", "de" to "German").size) { i ->
                val (code, label) = listOf("" to "Auto", "en" to "English", "zh" to "Chinese", "ja" to "Japanese", "ko" to "Korean", "es" to "Spanish", "fr" to "French", "de" to "German")[i]
                TvNavChip(
                    label = "Sub: $label",
                    onClick = {
                        settings.preferredSubtitleLanguage = code.ifEmpty { null }
                        status = "Subtitle language: $label"
                    }
                )
            }

item { SectionTitle("Storage") }
            item {
                TvNavChip(
                    label = "Clear image memory cache",
                    onClick = {
                        status = "Image cache cleared (session)"
                    }
                )
            }

            item { SectionTitle("About") }
            item {
                Text(
                    text = "Plex Android TV · Media3 / ExoPlayer",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
            item {
                Text(
                    text = "Auth token is never shown.",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (status.isNotBlank()) {
                item {
                    Text(
                        text = status,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 16.dp, bottom = 4.dp)
    )
}
