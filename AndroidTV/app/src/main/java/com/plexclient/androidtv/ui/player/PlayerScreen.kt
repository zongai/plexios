package com.plexclient.androidtv.ui.player

import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.PlayerView
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.plexclient.androidtv.playback.PlaybackRequest

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PlayerScreen(
    viewModel: PlayerViewModel,
    request: PlaybackRequest,
    onExit: () -> Unit
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(request.mediaUrl) {
        viewModel.play(request)
    }

    DisposableEffect(Unit) {
        onDispose { viewModel.release() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    useController = true
                    player = viewModel.playerForView()
                }
            },
            modifier = Modifier.fillMaxSize()
        )

        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(24.dp)
        ) {
            Text(
                text = "${state.title}\n${state.modeLabel} · ${state.status}",
                color = Color.White
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(top = 12.dp)
            ) {
                Surface(onClick = { viewModel.toggleTrackPanel() }) {
                    Text(text = "Audio / Subs", modifier = Modifier.padding(12.dp))
                }
                Surface(onClick = onExit) {
                    Text(text = "Exit", modifier = Modifier.padding(12.dp))
                }
            }
        }

        
        if (state.showSkipMarker) {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = androidx.compose.ui.Alignment.BottomEnd
            ) {
                Surface(
                    onClick = { viewModel.skipMarker() },
                    modifier = Modifier.padding(32.dp),
                    colors = ClickableSurfaceDefaults.colors(
                        containerColor = androidx.compose.ui.graphics.Color(0xFFE5A00D)
                    )
                ) {
                    Text(
                        text = state.skipMarkerLabel,
                        color = androidx.compose.ui.graphics.Color.Black,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
                    )
                }
            }
        }

        if (state.showTrackPanel) {
            Column(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .fillMaxWidth(0.35f)
                    .background(Color(0xCC121212))
                    .padding(16.dp)
            ) {
                Text(text = "Audio", color = Color.White)
                LazyColumn {
                    items(state.audioTracks) { track ->
                        Surface(onClick = { viewModel.selectAudio(track) }) {
                            Text(
                                text = (if (track.selected) "✓ " else "") + track.label,
                                modifier = Modifier.padding(10.dp),
                                color = Color.White
                            )
                        }
                    }
                }
                Text(text = "Subtitles", color = Color.White, modifier = Modifier.padding(top = 12.dp))
                Surface(onClick = { viewModel.selectSubtitle(null) }) {
                    Text(text = "Off", modifier = Modifier.padding(10.dp), color = Color.White)
                }
                LazyColumn {
                    items(state.subtitleTracks) { track ->
                        Surface(onClick = { viewModel.selectSubtitle(track) }) {
                            Text(
                                text = (if (track.selected) "✓ " else "") + track.label,
                                modifier = Modifier.padding(10.dp),
                                color = Color.White
                            )
                        }
                    }
                }
            }
        }
    }
}
