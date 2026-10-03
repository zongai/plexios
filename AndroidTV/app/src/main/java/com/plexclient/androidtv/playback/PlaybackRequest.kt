package com.plexclient.androidtv.playback

import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.model.ServerContext
import java.net.URI

data class PlaybackRequest(
    val metadata: PlexMetadata,
    val context: ServerContext,
    val network: NetworkClass,
    val decision: PlaybackDecision,
    val mediaUrl: URI,
    val startPositionMs: Long = 0
)
