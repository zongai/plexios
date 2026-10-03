package com.plexclient.androidtv.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.plexclient.androidtv.plex.image.PlexImage
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.model.PlexMetadataType
import com.plexclient.androidtv.plex.server.ConnectionManager
import com.plexclient.androidtv.ui.components.PosterCard
import com.plexclient.androidtv.ui.theme.TvLayout

/**
 * Official modern detail: dimmed backdrop + poster + gold Play CTA.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun DetailScreen(
    ratingKey: String,
    viewModel: DetailViewModel,
    connections: ConnectionManager,
    onBack: () -> Unit,
    onPlay: (PlexMetadata) -> Unit,
    onOpenChild: (PlexMetadata) -> Unit
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(ratingKey) {
        viewModel.load(ratingKey)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Dimmed art background (modern layout)
        state.item?.art?.let { artPath ->
            val artUrl = PlexImage.thumb(connections.context, artPath, width = 1280, height = 720)
            AsyncImage(
                model = artUrl,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
                alpha = 0.28f
            )
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, MaterialTheme.colorScheme.background)
                        )
                    )
            )
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(
                    horizontal = TvLayout.PagePaddingH.dp,
                    vertical = TvLayout.PagePaddingV.dp
                ),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                Surface(
                    onClick = onBack,
                    scale = ClickableSurfaceDefaults.scale(focusedScale = 1.06f),
                    colors = ClickableSurfaceDefaults.colors(
                        containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.85f)
                    ),
                    shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(6.dp))
                ) {
                    Text(text = "← Back", modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
                }
            }
            if (state.status.isNotBlank()) {
                item {
                    Text(
                        text = state.status,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            state.item?.let { item ->
                item {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(28.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        AsyncImage(
                            model = state.posterUrl,
                            contentDescription = item.title,
                            modifier = Modifier
                                .width(220.dp)
                                .height(330.dp),
                            contentScale = ContentScale.Crop
                        )
                        Column(
                            Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Text(
                                text = item.title,
                                style = MaterialTheme.typography.headlineLarge,
                                color = MaterialTheme.colorScheme.onBackground
                            )
                            val meta = listOfNotNull(
                                item.year?.toString(),
                                item.contentRating,
                                item.duration?.let { "${it / 60000} min" }
                            ).joinToString("  ·  ")
                            if (meta.isNotBlank()) {
                                Text(
                                    text = meta,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            item.tagline?.let {
                                Text(
                                    text = it,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            item.summary?.let {
                                Text(
                                    text = it,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.padding(top = 4.dp)
                                )
                            }
                            Spacer(Modifier.height(12.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                if (item.type in setOf(
                                        PlexMetadataType.Movie,
                                        PlexMetadataType.Episode,
                                        PlexMetadataType.Track
                                    )
                                ) {
                                    Surface(
                                        onClick = { onPlay(item) },
                                        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.06f),
                                        colors = ClickableSurfaceDefaults.colors(
                                            containerColor = MaterialTheme.colorScheme.primary,
                                            focusedContainerColor = MaterialTheme.colorScheme.primary
                                        ),
                                        shape = ClickableSurfaceDefaults.shape(
                                            shape = RoundedCornerShape(6.dp)
                                        )
                                    ) {
                                        Text(
                                            text = "▶  Play",
                                            color = Color.Black,
                                            style = MaterialTheme.typography.titleMedium,
                                            modifier = Modifier.padding(horizontal = 28.dp, vertical = 14.dp)
                                        )
                                    }
                                }
                                Surface(
                                    onClick = { viewModel.toggleFavorite() },
                                    scale = ClickableSurfaceDefaults.scale(focusedScale = 1.06f),
                                    colors = ClickableSurfaceDefaults.colors(
                                        containerColor = MaterialTheme.colorScheme.surface
                                    ),
                                    shape = ClickableSurfaceDefaults.shape(
                                        shape = RoundedCornerShape(6.dp)
                                    )
                                ) {
                                    Text(
                                        text = if (state.isFavorite) "Unfavorite" else "Favorite",
                                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if (state.children.isNotEmpty()) {
                item {
                    Text(
                        text = "Contents",
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        items(state.children) { child ->
                            val url = PlexImage.thumb(
                                connections.context,
                                child.thumb ?: child.parentThumb
                            )
                            PosterCard(
                                item = child,
                                posterUrl = url,
                                onClick = {
                                    if (child.type in setOf(
                                            PlexMetadataType.Movie,
                                            PlexMetadataType.Episode,
                                            PlexMetadataType.Track
                                        )
                                    ) onPlay(child) else onOpenChild(child)
                                }
                            )
                        }
                    }
                }
            }

            state.related.forEach { hub ->
                if (hub.items.isNotEmpty()) {
                    item {
                        Text(
                            text = hub.title.ifBlank { "Related" },
                            style = MaterialTheme.typography.titleLarge,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                    item {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            items(hub.items) { rel ->
                                val url = PlexImage.thumb(connections.context, rel.thumb)
                                PosterCard(item = rel, posterUrl = url, onClick = { onOpenChild(rel) })
                            }
                        }
                    }
                }
            }
        }
    }
}
