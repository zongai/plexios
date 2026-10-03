package com.plexclient.androidtv.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import androidx.compose.foundation.BorderStroke
import coil.compose.AsyncImage
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.ui.theme.TvLayout

/**
 * Official TV-style poster: artwork-first, title under, gold focus ring + scale.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PosterCard(
    item: PlexMetadata,
    posterUrl: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val w = TvLayout.CardWidth.dp
    Surface(
        onClick = onClick,
        modifier = modifier.width(w),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.12f),
        border = ClickableSurfaceDefaults.border(
            focusedBorder = Border(
                border = BorderStroke(
                    TvLayout.FocusBorderWidth.dp,
                    com.plexclient.androidtv.ui.theme.PlexColors.accent
                ),
                shape = RoundedCornerShape(6.dp)
            )
        ),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = MaterialTheme.colorScheme.surface,
            focusedContainerColor = MaterialTheme.colorScheme.surface
        ),
        shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(6.dp))
    ) {
        Column {
            AsyncImage(
                model = posterUrl,
                contentDescription = item.title,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(TvLayout.CardPosterHeight.dp),
                contentScale = ContentScale.Crop
            )
            Column(Modifier.padding(horizontal = 6.dp, vertical = 8.dp)) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurface
                )
                item.year?.let {
                    Text(
                        text = it.toString(),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}
