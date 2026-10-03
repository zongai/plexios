package com.plexclient.androidtv.ui.collections

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

data class CollectionsUiState(
    val collections: List<PlexMetadata> = emptyList(),
    val children: List<PlexMetadata> = emptyList(),
    val showingChildren: Boolean = false,
    val title: String = "Collections",
    val status: String = "",
    val loading: Boolean = false
)

class CollectionsViewModel(
    private val api: PlexApiClient,
    private val connections: ConnectionManager
) : ViewModel() {
    private val _state = MutableStateFlow(CollectionsUiState())
    val state: StateFlow<CollectionsUiState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            val base = connections.activeBaseUrl
            val token = connections.activeToken
            if (base == null || token.isNullOrBlank()) {
                _state.update { it.copy(status = "No active server") }
                return@launch
            }
            _state.update { it.copy(loading = true, showingChildren = false, title = "Collections") }
            try {
                var list = api.fetchCollections(base, token).toMutableList()
                if (list.isEmpty()) {
                    val sections = api.fetchLibrarySections(base, token)
                    val seen = mutableSetOf<String>()
                    for (section in sections) {
                        for (c in api.fetchSectionCollections(section.key, base, token)) {
                            if (seen.add(c.ratingKey)) list.add(c)
                        }
                    }
                }
                _state.update {
                    it.copy(
                        collections = list,
                        loading = false,
                        status = if (list.isEmpty()) "No collections" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    fun openCollection(item: PlexMetadata) {
        viewModelScope.launch {
            val base = connections.activeBaseUrl ?: return@launch
            val token = connections.activeToken ?: return@launch
            _state.update { it.copy(loading = true, title = item.title) }
            try {
                val children = api.fetchCollectionChildren(item.ratingKey, base, token)
                _state.update {
                    it.copy(
                        children = children,
                        showingChildren = true,
                        loading = false,
                        status = if (children.isEmpty()) "Empty collection" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    fun backToList() {
        _state.update {
            it.copy(showingChildren = false, title = "Collections", children = emptyList(), status = "")
        }
    }

    fun posterUrl(item: PlexMetadata): String? =
        PlexImage.thumb(connections.context, item.thumb ?: item.parentThumb)

    class Factory(
        private val api: PlexApiClient,
        private val connections: ConnectionManager
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            CollectionsViewModel(api, connections) as T
    }
}
