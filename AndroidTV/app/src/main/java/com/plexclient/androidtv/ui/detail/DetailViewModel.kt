package com.plexclient.androidtv.ui.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.image.PlexImage
import com.plexclient.androidtv.plex.model.PlexHub
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.model.PlexMetadataType
import com.plexclient.androidtv.plex.server.ConnectionManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class DetailUiState(
    val item: PlexMetadata? = null,
    val children: List<PlexMetadata> = emptyList(),
    val related: List<PlexHub> = emptyList(),
    val posterUrl: String? = null,
    val isFavorite: Boolean = false,
    val status: String = "",
    val loading: Boolean = false
)

class DetailViewModel(
    private val api: PlexApiClient,
    private val connections: ConnectionManager
) : ViewModel() {
    private val _state = MutableStateFlow(DetailUiState())
    val state: StateFlow<DetailUiState> = _state.asStateFlow()

    fun load(ratingKey: String) {
        viewModelScope.launch {
            val base = connections.activeBaseUrl
            val token = connections.activeToken
            if (base == null || token.isNullOrBlank()) {
                _state.update { it.copy(status = "No active server") }
                return@launch
            }
            _state.update { it.copy(loading = true, status = "") }
            try {
                val item = api.fetchMetadata(ratingKey, base, token)
                val ctx = connections.context
                val poster = PlexImage.thumb(ctx, item.thumb ?: item.parentThumb ?: item.grandparentThumb)
                var children = emptyList<PlexMetadata>()
                if (item.type in setOf(
                        PlexMetadataType.Show, PlexMetadataType.Season,
                        PlexMetadataType.Artist, PlexMetadataType.Album
                    )
                ) {
                    children = api.fetchChildren(ratingKey, base, token)
                }
                val related = try {
                    api.fetchRelated(ratingKey, base, token)
                } catch (_: Exception) {
                    emptyList()
                }
                _state.update {
                    it.copy(
                        item = item,
                        children = children,
                        related = related,
                        posterUrl = poster,
                        isFavorite = item.isFavorite,
                        loading = false
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    fun toggleFavorite() {
        viewModelScope.launch {
            val item = _state.value.item ?: return@launch
            val base = connections.activeBaseUrl ?: return@launch
            val token = connections.activeToken ?: return@launch
            val next = !_state.value.isFavorite
            try {
                // Plex: key path (e.g. /library/metadata/123), rating 10 = favorite, 0 = clear
                api.rate(item.key, if (next) 10 else 0, base, token)
                _state.update {
                    it.copy(
                        isFavorite = next,
                        status = if (next) "Added to favorites" else "Removed from favorites"
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(status = e.message ?: "Rate failed") }
            }
        }
    }

    class Factory(
        private val api: PlexApiClient,
        private val connections: ConnectionManager
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            DetailViewModel(api, connections) as T
    }
}
