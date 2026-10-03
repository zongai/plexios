package com.plexclient.androidtv.ui.libraries

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.model.PlexLibrary
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.server.ConnectionManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class LibrariesUiState(
    val libraries: List<PlexLibrary> = emptyList(),
    val items: List<PlexMetadata> = emptyList(),
    val title: String = "Libraries",
    val status: String = "",
    val loading: Boolean = false
)

class LibrariesViewModel(
    private val api: PlexApiClient,
    private val connections: ConnectionManager
) : ViewModel() {
    private val _state = MutableStateFlow(LibrariesUiState())
    val state: StateFlow<LibrariesUiState> = _state.asStateFlow()

    fun loadLibraries() {
        viewModelScope.launch {
            val base = connections.activeBaseUrl
            val token = connections.activeToken
            if (base == null || token.isNullOrBlank()) {
                _state.update { it.copy(status = "No active server") }
                return@launch
            }
            _state.update { it.copy(loading = true) }
            try {
                val libs = api.fetchLibrarySections(base, token)
                _state.update { it.copy(libraries = libs, loading = false) }
                libs.firstOrNull()?.let { selectLibrary(it) }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    fun selectLibrary(library: PlexLibrary) {
        viewModelScope.launch {
            val base = connections.activeBaseUrl ?: return@launch
            val token = connections.activeToken ?: return@launch
            _state.update { it.copy(title = library.title, loading = true, status = "") }
            try {
                val items = api.fetchLibraryAll(library.key, base, token)
                _state.update {
                    it.copy(
                        items = items,
                        loading = false,
                        status = if (items.isEmpty()) "Empty library" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    class Factory(
        private val api: PlexApiClient,
        private val connections: ConnectionManager
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            LibrariesViewModel(api, connections) as T
    }
}
