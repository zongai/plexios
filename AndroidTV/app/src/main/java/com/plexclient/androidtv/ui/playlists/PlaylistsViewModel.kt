package com.plexclient.androidtv.ui.playlists

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.image.PlexImage
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.server.ConnectionManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PlaylistsUiState(
    val playlists: List<PlexMetadata> = emptyList(),
    val items: List<PlexMetadata> = emptyList(),
    val showingItems: Boolean = false,
    val title: String = "Playlists",
    val status: String = "",
    val loading: Boolean = false
)

class PlaylistsViewModel(
    private val api: PlexApiClient,
    private val connections: ConnectionManager
) : ViewModel() {
    private val _state = MutableStateFlow(PlaylistsUiState())
    val state: StateFlow<PlaylistsUiState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            val base = connections.activeBaseUrl
            val token = connections.activeToken
            if (base == null || token.isNullOrBlank()) {
                _state.update { it.copy(status = "No active server") }
                return@launch
            }
            _state.update { it.copy(loading = true, showingItems = false, title = "Playlists") }
            try {
                val list = api.fetchPlaylists(base, token)
                _state.update {
                    it.copy(
                        playlists = list,
                        loading = false,
                        status = if (list.isEmpty()) "No playlists" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    fun openPlaylist(item: PlexMetadata) {
        viewModelScope.launch {
            val base = connections.activeBaseUrl ?: return@launch
            val token = connections.activeToken ?: return@launch
            _state.update { it.copy(loading = true, title = item.title) }
            try {
                val items = api.fetchPlaylistItems(item.ratingKey, base, token)
                _state.update {
                    it.copy(
                        items = items,
                        showingItems = true,
                        loading = false,
                        status = if (items.isEmpty()) "Empty playlist" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    fun backToList() {
        _state.update {
            it.copy(showingItems = false, title = "Playlists", items = emptyList(), status = "")
        }
    }

    fun posterUrl(item: PlexMetadata): String? =
        PlexImage.thumb(connections.context, item.thumb ?: item.parentThumb ?: item.grandparentThumb)

    class Factory(
        private val api: PlexApiClient,
        private val connections: ConnectionManager
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            PlaylistsViewModel(api, connections) as T
    }
}
