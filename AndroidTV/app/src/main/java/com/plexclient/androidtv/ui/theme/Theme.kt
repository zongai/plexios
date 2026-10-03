package com.plexclient.androidtv.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme

/**
 * Official Plex big-screen visual language:
 * near-black canvas, elevated surfaces, gold accent #E5A00D, high-contrast focus.
 */
private val PlexAccent = Color(0xFFE5A00D)
private val PlexBg = Color(0xFF121212)
private val PlexSurface = Color(0xFF1B1B1B)
private val PlexSurfaceVariant = Color(0xFF282828)
private val PlexSidebar = Color(0xFF191919)
private val PlexOnSurface = Color(0xFFF5F5F5)
private val PlexOnSurfaceVariant = Color(0xFFA3A3A3)

object PlexColors {
    val accent = PlexAccent
    val background = PlexBg
    val surface = PlexSurface
    val surfaceVariant = PlexSurfaceVariant
    val sidebar = PlexSidebar
    val onSurface = PlexOnSurface
    val onSurfaceVariant = PlexOnSurfaceVariant
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PlexTvTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = PlexAccent,
            onPrimary = Color.Black,
            secondary = PlexAccent,
            onSecondary = Color.Black,
            tertiary = PlexAccent,
            background = PlexBg,
            onBackground = PlexOnSurface,
            surface = PlexSurface,
            onSurface = PlexOnSurface,
            surfaceVariant = PlexSurfaceVariant,
            onSurfaceVariant = PlexOnSurfaceVariant,
            border = Color(0x33FFFFFF),
            focusedBorder = PlexAccent,
            errorContainer = Color(0xFF3D1A1A)
        ),
        content = content
    )
}

/** TV layout tokens — 10-foot UI + overscan safety. */
object TvLayout {
    /** ~5% overscan horizontal inset */
    val PagePaddingH = 48
    val PagePaddingV = 28
    val HubSpacing = 32
    /** Classic poster aspect ~2:3 */
    val CardWidth = 148
    val CardPosterHeight = 222
    val SidebarWidth = 220
    val FocusBorderWidth = 3
}
