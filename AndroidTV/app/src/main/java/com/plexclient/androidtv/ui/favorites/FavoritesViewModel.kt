package com.plexclient.androidtv.ui.favorites

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

data class FavoritesUiState(
    val items: List<PlexMetadata> = emptyList(),
    val status: String = "",
    val loading: Boolean = false
)

class FavoritesViewModel(
    private val api: PlexApiClient,
    private val connections: ConnectionManager
) : ViewModel() {
    private val _state = MutableStateFlow(FavoritesUiState())
    val state: StateFlow<FavoritesUiState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            val base = connections.activeBaseUrl
            val token = connections.activeToken
            if (base == null || token.isNullOrBlank()) {
                _state.update { it.copy(status = "No active server") }
                return@launch
            }
            _state.update { it.copy(loading = true, status = "") }
            try {
                val items = api.fetchFavorites(base, token)
                _state.update {
                    it.copy(
                        items = items,
                        loading = false,
                        status = if (items.isEmpty()) "No favorites yet" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
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
            FavoritesViewModel(api, connections) as T
    }
}
