package com.plexclient.androidtv.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.plexclient.androidtv.plex.image.PlexImage
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.server.ConnectionManager
import com.plexclient.androidtv.ui.components.PosterCard

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SearchScreen(
    viewModel: SearchViewModel,
    connections: ConnectionManager,
    onBack: () -> Unit,
    onOpenItem: (PlexMetadata) -> Unit
) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF121212))
            .padding(24.dp)
    ) {
        Surface(onClick = onBack) {
            Text(text = "← Back", modifier = Modifier.padding(12.dp))
        }
        Text(
            text = "Search",
            style = androidx.tv.material3.MaterialTheme.typography.headlineLarge,
            modifier = Modifier.padding(vertical = 12.dp)
        )
        // TV-friendly: show current query + D-pad friendly preset; full soft keyboard via system
        androidx.compose.material3.OutlinedTextField(
            value = state.query,
            onValueChange = { viewModel.onQueryChange(it) },
            modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
            singleLine = true,
            label = { androidx.compose.material3.Text("Query") }
        )
        if (state.status.isNotBlank()) {
            Text(text = state.status, color = Color(0xFFB0B0B0))
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            items(state.hubs) { hub ->
                Column {
                    Text(
                        text = hub.title,
                        style = androidx.tv.material3.MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(bottom = 8.dp)
                    )
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
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
