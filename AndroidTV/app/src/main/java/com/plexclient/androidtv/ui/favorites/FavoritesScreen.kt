package com.plexclient.androidtv.ui.favorites

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Surface
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.ui.components.PosterCard

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun FavoritesScreen(
    viewModel: FavoritesViewModel,
    onBack: () -> Unit,
    onOpenItem: (PlexMetadata) -> Unit
) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(Unit) { viewModel.load() }

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
            text = "Favorites",
            style = androidx.tv.material3.MaterialTheme.typography.headlineLarge,
            modifier = Modifier.padding(vertical = 12.dp)
        )
        if (state.status.isNotBlank()) Text(text = state.status)

        LazyVerticalGrid(
            columns = GridCells.Adaptive(140.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize()
        ) {
            items(state.items) { item ->
                PosterCard(
                    item = item,
                    posterUrl = viewModel.posterUrl(item),
                    onClick = { onOpenItem(item) }
                )
            }
        }
    }
}
