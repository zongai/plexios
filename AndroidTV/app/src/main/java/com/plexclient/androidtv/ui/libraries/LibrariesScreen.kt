package com.plexclient.androidtv.ui.libraries

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items as lazyItems
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Surface
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.plexclient.androidtv.plex.image.PlexImage
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.server.ConnectionManager
import com.plexclient.androidtv.ui.components.PosterCard

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun LibrariesScreen(
    viewModel: LibrariesViewModel,
    connections: ConnectionManager,
    onOpenItem: (PlexMetadata) -> Unit,
    onBack: () -> Unit
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.loadLibraries()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 48.dp, vertical = 32.dp)
    ) {
        Surface(onClick = onBack) {
            Text(text = "← Back", modifier = Modifier.padding(12.dp))
        }
        Text(
            text = state.title,
            style = androidx.tv.material3.MaterialTheme.typography.headlineLarge,
            modifier = Modifier.padding(vertical = 12.dp)
        )
        if (state.status.isNotBlank()) {
            Text(text = state.status)
        }

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(vertical = 12.dp)
        ) {
            lazyItems(state.libraries) { lib ->
                Surface(
                    onClick = { viewModel.selectLibrary(lib) },
                    scale = ClickableSurfaceDefaults.scale(focusedScale = 1.06f)
                ) {
                    Text(text = lib.title, modifier = Modifier.padding(14.dp))
                }
            }
        }

        LazyVerticalGrid(
            columns = GridCells.Adaptive(140.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize()
        ) {
            items(state.items) { item ->
                val url = PlexImage.thumb(connections.context, item.thumb)
                PosterCard(item = item, posterUrl = url, onClick = { onOpenItem(item) })
            }
        }
    }
}
