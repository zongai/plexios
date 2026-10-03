package com.plexclient.androidtv.ui.iptv

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.plexclient.androidtv.iptv.IptvChannel
import com.plexclient.androidtv.iptv.IptvPlaylist
import com.plexclient.androidtv.iptv.IptvRepository
import com.plexclient.androidtv.ui.components.TvNavChip
import com.plexclient.androidtv.ui.components.TvPage
import kotlinx.coroutines.launch

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun IptvScreen(
    repo: IptvRepository,
    onBack: () -> Unit,
    onPlayChannel: (IptvChannel) -> Unit
) {
    var playlists by remember { mutableStateOf(repo.loadPlaylists()) }
    var channels by remember { mutableStateOf(repo.allEnabledChannels()) }
    var status by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun reload() {
        playlists = repo.loadPlaylists()
        channels = repo.allEnabledChannels()
        status = if (channels.isEmpty()) "Add an M3U playlist URL" else "${channels.size} channels"
    }

    LaunchedEffect(Unit) { reload() }

    TvPage(title = "IPTV", onBack = onBack) {
        Text(text = status, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)

        Text(text = "Playlist name", style = MaterialTheme.typography.labelLarge)
        BasicTextField(
            value = name,
            onValueChange = { name = it },
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 6.dp)
        )
        Text(text = "M3U URL", style = MaterialTheme.typography.labelLarge)
        BasicTextField(
            value = url,
            onValueChange = { url = it },
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 6.dp)
        )

        TvNavChip(
            label = if (busy) "Working…" else "Add & Refresh playlist",
            onClick = {
                if (busy || url.isBlank()) return@TvNavChip
                scope.launch {
                    busy = true
                    try {
                        val pl = IptvPlaylist(
                            id = IptvRepository.newId(),
                            name = name.ifBlank { "Playlist" },
                            url = url.trim()
                        )
                        repo.addPlaylist(pl)
                        repo.refreshPlaylist(pl)
                        name = ""
                        url = ""
                        reload()
                        status = "Loaded ${pl.channelCount} channels"
                    } catch (e: Exception) {
                        status = e.message ?: "Add failed"
                    } finally {
                        busy = false
                    }
                }
            }
        )
        TvNavChip(
            label = "Refresh all",
            onClick = {
                scope.launch {
                    busy = true
                    try {
                        repo.loadPlaylists().forEach { repo.refreshPlaylist(it) }
                        reload()
                        status = "Refreshed"
                    } catch (e: Exception) {
                        status = e.message ?: "Refresh failed"
                    } finally {
                        busy = false
                    }
                }
            }
        )

        Text(
            text = "Playlists",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(top = 12.dp)
        )
        playlists.forEach { pl ->
            TvNavChip(
                label = "Delete ${pl.name} (${pl.channelCount})",
                onClick = {
                    repo.deletePlaylist(pl.id)
                    reload()
                }
            )
        }

        Text(
            text = "Channels",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(top = 12.dp)
        )
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(channels.take(150), key = { it.id }) { ch ->
                TvNavChip(
                    label = "${ch.name}${ch.group?.let { " · $it" } ?: ""}",
                    onClick = { onPlayChannel(ch) }
                )
            }
        }
    }
}
