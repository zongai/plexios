package com.plexclient.androidtv.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.plexclient.androidtv.plex.image.PlexImage
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.server.ConnectionManager
import com.plexclient.androidtv.ui.components.PosterCard
import com.plexclient.androidtv.ui.components.TvSideNav
import com.plexclient.androidtv.ui.theme.TvLayout

/**
 * Official big-screen home: left source nav + horizontal recommendation rows.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    connections: ConnectionManager,
    onOpenItem: (PlexMetadata) -> Unit,
    onOpenLibraries: () -> Unit,
    onOpenSearch: () -> Unit,
    onOpenCollections: () -> Unit,
    onOpenPlaylists: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenFavorites: () -> Unit,
    onOpenIptv: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(Unit) { viewModel.load() }

    TvSideNav(
        selected = "home",
        onSelect = { id ->
            when (id) {
                "libraries" -> onOpenLibraries()
                "search" -> onOpenSearch()
                "collections" -> onOpenCollections()
                "playlists" -> onOpenPlaylists()
                "favorites" -> onOpenFavorites()
                "settings" -> onOpenSettings()
                "iptv" -> onOpenIptv()
            }
        }
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = "Home",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onBackground
            )
            if (state.status.isNotBlank()) {
                Text(
                    text = state.status,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(TvLayout.HubSpacing.dp),
                contentPadding = PaddingValues(bottom = 48.dp)
            ) {
                items(state.hubs) { hub ->
                    Column {
                        Text(
                            text = hub.title,
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onBackground,
                            modifier = Modifier.padding(bottom = 12.dp)
                        )
                        LazyRow(
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                            contentPadding = PaddingValues(end = 24.dp)
                        ) {
                            items(hub.items) { item ->
                                val url = PlexImage.thumb(
                                    connections.context,
                                    item.thumb ?: item.parentThumb ?: item.grandparentThumb
                                )
                                PosterCard(item = item, posterUrl = url, onClick = { onOpenItem(item) })
                            }
                        }
                    }
                }
            }
        }
    }
}
