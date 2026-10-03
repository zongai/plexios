package com.plexclient.androidtv.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import androidx.compose.foundation.BorderStroke
import com.plexclient.androidtv.ui.theme.PlexColors
import com.plexclient.androidtv.ui.theme.TvLayout

/** Overscan-safe page chrome for Android TV. */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun TvPage(
    title: String? = null,
    onBack: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(
                horizontal = TvLayout.PagePaddingH.dp,
                vertical = TvLayout.PagePaddingV.dp
            ),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        if (onBack != null || title != null) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (onBack != null) {
                    Surface(
                        onClick = onBack,
                        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.06f),
                        colors = ClickableSurfaceDefaults.colors(
                            containerColor = MaterialTheme.colorScheme.surface
                        ),
                        shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(6.dp))
                    ) {
                        Text(
                            text = "Back",
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                            style = MaterialTheme.typography.labelLarge
                        )
                    }
                }
                if (title != null) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.headlineMedium,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                }
            }
        }
        content()
    }
}

/**
 * Left navigation rail matching official big-screen Plex (sources on the left).
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun TvSideNav(
    selected: String,
    onSelect: (String) -> Unit,
    content: @Composable () -> Unit
) {
    Row(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Column(
            modifier = Modifier
                .width(TvLayout.SidebarWidth.dp)
                .fillMaxHeight()
                .background(PlexColors.sidebar)
                .padding(vertical = TvLayout.PagePaddingV.dp, horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = "Plex",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
            )
            Spacer(Modifier.height(8.dp))
            listOf(
                "home" to "Home",
                "libraries" to "Libraries",
                "search" to "Search",
                "collections" to "Collections",
                "playlists" to "Playlists",
                "favorites" to "Favorites",
                "settings" to "Settings"
            ).forEach { (id, label) ->
                val isSelected = selected == id
                Surface(
                    onClick = { onSelect(id) },
                    modifier = Modifier.fillMaxWidth(),
                    scale = ClickableSurfaceDefaults.scale(focusedScale = 1.04f),
                    border = ClickableSurfaceDefaults.border(
                        focusedBorder = Border(
                            border = BorderStroke(2.dp, MaterialTheme.colorScheme.focusedBorder),
                            shape = RoundedCornerShape(8.dp)
                        )
                    ),
                    colors = ClickableSurfaceDefaults.colors(
                        containerColor = if (isSelected)
                            MaterialTheme.colorScheme.primary.copy(alpha = 0.22f)
                        else
                            MaterialTheme.colorScheme.surface.copy(alpha = 0f),
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant
                    ),
                    shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(8.dp))
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.titleSmall,
                        color = if (isSelected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)
                    )
                }
            }
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
                .padding(
                    start = 8.dp,
                    end = TvLayout.PagePaddingH.dp,
                    top = TvLayout.PagePaddingV.dp,
                    bottom = TvLayout.PagePaddingV.dp
                )
        ) {
            content()
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun TvNavChip(label: String, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.08f),
        border = ClickableSurfaceDefaults.border(
            focusedBorder = Border(
                border = BorderStroke(2.dp, MaterialTheme.colorScheme.focusedBorder),
                shape = RoundedCornerShape(24.dp)
            )
        ),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = MaterialTheme.colorScheme.surface,
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant
        ),
        shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(24.dp))
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
        )
    }
}
