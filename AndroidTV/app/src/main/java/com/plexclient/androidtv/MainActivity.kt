package com.plexclient.androidtv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Column
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Text
import com.plexclient.androidtv.playback.NetworkClass
import com.plexclient.androidtv.playback.PlaybackRequest
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.model.PlexMetadataType
import com.plexclient.androidtv.ui.collections.CollectionsScreen
import com.plexclient.androidtv.ui.collections.CollectionsViewModel
import com.plexclient.androidtv.ui.favorites.FavoritesScreen
import com.plexclient.androidtv.ui.favorites.FavoritesViewModel
import com.plexclient.androidtv.ui.detail.DetailScreen
import com.plexclient.androidtv.ui.detail.DetailViewModel
import com.plexclient.androidtv.ui.home.HomeScreen
import com.plexclient.androidtv.ui.home.HomeViewModel
import com.plexclient.androidtv.ui.libraries.LibrariesScreen
import com.plexclient.androidtv.ui.libraries.LibrariesViewModel
import com.plexclient.androidtv.ui.player.PlayerScreen
import com.plexclient.androidtv.ui.player.PlayerViewModel
import com.plexclient.androidtv.ui.playlists.PlaylistsScreen
import com.plexclient.androidtv.ui.playlists.PlaylistsViewModel
import com.plexclient.androidtv.ui.search.SearchScreen
import com.plexclient.androidtv.ui.search.SearchViewModel
import com.plexclient.androidtv.ui.settings.SettingsScreen
import com.plexclient.androidtv.ui.iptv.IptvScreen
import com.plexclient.androidtv.iptv.IptvChannel
import com.plexclient.androidtv.playback.PlaybackMode
import com.plexclient.androidtv.playback.PlaybackDecision
import com.plexclient.androidtv.plex.model.ServerContext
import java.net.URI
import com.plexclient.androidtv.ui.signIn.SignInScreen
import com.plexclient.androidtv.ui.signIn.SignInViewModel
import com.plexclient.androidtv.ui.theme.PlexTvTheme
import kotlinx.coroutines.launch

sealed class Screen {
    data object SignIn : Screen()
    data object Discovering : Screen()
    data object Home : Screen()
    data object Libraries : Screen()
    data object Search : Screen()
    data object Collections : Screen()
    data object Playlists : Screen()
    data object Settings : Screen()
    data object Favorites : Screen()
    data object Iptv : Screen()
    data class Detail(val ratingKey: String, val from: Screen = Home) : Screen()
    data class Player(val request: PlaybackRequest, val from: Screen = Home) : Screen()
}

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalTvMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as PlexApp
        val c = app.container

        setContent {
            PlexTvTheme {
                var screen by remember {
                    mutableStateOf<Screen>(
                        if (c.auth.isSignedIn) Screen.Discovering else Screen.SignIn
                    )
                }
                val scope = rememberCoroutineScope()

                fun openDetail(meta: PlexMetadata, from: Screen) {
                    screen = Screen.Detail(meta.ratingKey, from)
                }

                fun openPlayback(meta: PlexMetadata, from: Screen) {
                    scope.launch {
                        buildPlayback(meta)?.let { screen = Screen.Player(it, from) }
                    }
                }

                when (val s = screen) {
                    Screen.SignIn -> {
                        val vm: SignInViewModel = viewModel(factory = SignInViewModel.Factory(c.auth))
                        SignInScreen(vm) { screen = Screen.Discovering }
                    }
                    Screen.Discovering -> {
                        DiscoveringServer(
                            onReady = { screen = Screen.Home },
                            onRetry = { screen = Screen.Discovering },
                            onSignOut = {
                                c.auth.signOut()
                                screen = Screen.SignIn
                            }
                        )
                    }
                    Screen.Home -> {
                        val vm: HomeViewModel = viewModel(
                            factory = HomeViewModel.Factory(c.api, c.connections, c.settings)
                        )
                        HomeScreen(
                            viewModel = vm,
                            connections = c.connections,
                            onOpenLibraries = { screen = Screen.Libraries },
                            onOpenSearch = { screen = Screen.Search },
                            onOpenCollections = { screen = Screen.Collections },
                            onOpenPlaylists = { screen = Screen.Playlists },
                            onOpenSettings = { screen = Screen.Settings },
                            onOpenFavorites = { screen = Screen.Favorites },
                            onOpenIptv = { screen = Screen.Iptv },
                            onOpenItem = { openDetail(it, Screen.Home) }
                        )
                    }
                    Screen.Favorites -> {
                        val vm: FavoritesViewModel = viewModel(
                            factory = FavoritesViewModel.Factory(c.api, c.connections)
                        )
                        FavoritesScreen(
                            viewModel = vm,
                            onBack = { screen = Screen.Home },
                            onOpenItem = { openDetail(it, Screen.Favorites) }
                        )
                    }
                    
                    Screen.Iptv -> {
                        IptvScreen(
                            repo = c.iptvRepository,
                            onBack = { screen = Screen.Home },
                            onPlayChannel = { ch ->
                                buildIptvPlayback(ch)?.let { screen = Screen.Player(it, Screen.Iptv) }
                            }
                        )
                    }

                    Screen.Settings -> {
                        SettingsScreen(
                            settings = c.settings,
                            auth = c.auth,
                            connections = c.connections,
                            onBack = { screen = Screen.Home },
                            onSignedOut = { screen = Screen.SignIn }
                        )
                    }
                    Screen.Libraries -> {
                        val vm: LibrariesViewModel = viewModel(
                            factory = LibrariesViewModel.Factory(c.api, c.connections)
                        )
                        LibrariesScreen(
                            viewModel = vm,
                            connections = c.connections,
                            onBack = { screen = Screen.Home },
                            onOpenItem = { openDetail(it, Screen.Libraries) }
                        )
                    }
                    Screen.Search -> {
                        val vm: SearchViewModel = viewModel(
                            factory = SearchViewModel.Factory(c.api, c.connections)
                        )
                        SearchScreen(
                            viewModel = vm,
                            connections = c.connections,
                            onBack = { screen = Screen.Home },
                            onOpenItem = { openDetail(it, Screen.Search) }
                        )
                    }
                    Screen.Collections -> {
                        val vm: CollectionsViewModel = viewModel(
                            factory = CollectionsViewModel.Factory(c.api, c.connections)
                        )
                        CollectionsScreen(
                            viewModel = vm,
                            onBack = { screen = Screen.Home },
                            onOpenItem = { openDetail(it, Screen.Collections) }
                        )
                    }
                    Screen.Playlists -> {
                        val vm: PlaylistsViewModel = viewModel(
                            factory = PlaylistsViewModel.Factory(c.api, c.connections)
                        )
                        PlaylistsScreen(
                            viewModel = vm,
                            onBack = { screen = Screen.Home },
                            onOpenItem = { openDetail(it, Screen.Playlists) }
                        )
                    }
                    is Screen.Detail -> {
                        val vm: DetailViewModel = viewModel(
                            factory = DetailViewModel.Factory(c.api, c.connections)
                        )
                        DetailScreen(
                            ratingKey = s.ratingKey,
                            viewModel = vm,
                            connections = c.connections,
                            onBack = { screen = s.from },
                            onPlay = { openPlayback(it, s) },
                            onOpenChild = { openDetail(it, s) }
                        )
                    }
                    is Screen.Player -> {
                        val vm: PlayerViewModel = viewModel(
                            factory = PlayerViewModel.Factory(
                                application,
                                c.api,
                                c.decisionEngine(),
                                c.urlBuilder,
                                c.timeline,
                                c.settings
                            )
                        )
                        PlayerScreen(
                            viewModel = vm,
                            request = s.request,
                            onExit = { screen = s.from }
                        )
                    }
                }
            }
        }
    }

    @Composable
    private fun DiscoveringServer(
        onReady: () -> Unit,
        onRetry: () -> Unit,
        onSignOut: () -> Unit
    ) {
        val app = application as PlexApp
        val c = app.container
        var status by remember { mutableStateOf("Discovering servers…") }
        var failed by remember { mutableStateOf(false) }
        // Bump key to re-run discovery after Retry
        var attempt by remember { mutableStateOf(0) }

        LaunchedEffect(attempt) {
            failed = false
            status = "Discovering servers…"
            try {
                val token = c.auth.token.value
                if (token.isNullOrBlank()) {
                    status = "Not signed in"
                    failed = true
                    return@LaunchedEffect
                }
                val ranked = c.connections.discoverAndRank(token)
                if (ranked.isEmpty()) {
                    status = "No servers found. Check that PMS is online and this account has access."
                    failed = true
                    return@LaunchedEffect
                }
                c.connections.selectBest(ranked)
                status = "Connected to ${c.connections.activeServer?.name}"
                onReady()
            } catch (e: Exception) {
                status = e.message ?: "Discovery failed"
                failed = true
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(48.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = status,
                style = androidx.tv.material3.MaterialTheme.typography.titleLarge,
                color = androidx.tv.material3.MaterialTheme.colorScheme.onBackground
            )
            if (failed) {
                Spacer(Modifier.height(24.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    androidx.tv.material3.Surface(onClick = { attempt += 1 }) {
                        Text(
                            text = "Retry",
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
                        )
                    }
                    androidx.tv.material3.Surface(onClick = onSignOut) {
                        Text(
                            text = "Sign out",
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)
                        )
                    }
                }
            }
        }
    }

    
    private fun buildIptvPlayback(ch: com.plexclient.androidtv.iptv.IptvChannel): PlaybackRequest? {
        return try {
            val url = java.net.URI(ch.streamUrl)
            val meta = PlexMetadata(
                ratingKey = "iptv-${ch.id}",
                key = "/iptv/${ch.id}",
                type = PlexMetadataType.Unknown,
                title = ch.name,
                summary = null,
                year = null,
                thumb = ch.logoUrl,
                art = null,
                parentThumb = null,
                grandparentThumb = null,
                parentTitle = null,
                grandparentTitle = null,
                parentRatingKey = null,
                grandparentRatingKey = null,
                index = null,
                parentIndex = null,
                duration = null,
                viewOffset = null,
                contentRating = null,
                studio = null,
                tagline = null,
                media = emptyList()
            )
            val ctx = ServerContext(java.net.URI("http://localhost/"), "", "iptv")
            PlaybackRequest(
                metadata = meta,
                context = ctx,
                network = NetworkClass.Local,
                decision = PlaybackDecision(PlaybackMode.DirectPlay, "IPTV direct"),
                mediaUrl = url,
                startPositionMs = 0
            )
        } catch (_: Exception) {
            null
        }
    }

private suspend fun buildPlayback(meta: PlexMetadata): PlaybackRequest? {
        val app = application as PlexApp
        val c = app.container
        val ctx = c.connections.context ?: return null

        // Ensure full metadata with media parts for decision
        val full = try {
            if (meta.media.isEmpty()) {
                c.api.fetchMetadata(meta.ratingKey, ctx.baseUrl, ctx.token)
            } else meta
        } catch (_: Exception) {
            meta
        }

        // Non-playable containers → no player (Detail already handles drill-down)
        if (full.type !in setOf(
                PlexMetadataType.Movie,
                PlexMetadataType.Episode,
                PlexMetadataType.Track,
                PlexMetadataType.Clip
            )
        ) return null

        val network = c.connections.networkClass
        val decision = c.decisionEngine().decide(full, network)
        val url = c.urlBuilder.build(ctx, full, decision)
        val start = full.viewOffset ?: 0L
        val duration = full.duration ?: 0L
        val startMs = if (duration > 0 && start > duration * 0.95) 0L else start
        return PlaybackRequest(
            metadata = full,
            context = ctx,
            network = network,
            decision = decision,
            mediaUrl = url,
            startPositionMs = startMs
        )
    }
}
