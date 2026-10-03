package com.plexclient.androidtv.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.model.PlexHub
import com.plexclient.androidtv.plex.server.ConnectionManager
import com.plexclient.androidtv.settings.AppSettings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class HomeUiState(
    val hubs: List<PlexHub> = emptyList(),
    val status: String = "",
    val loading: Boolean = false
)

class HomeViewModel(
    private val api: PlexApiClient,
    private val connections: ConnectionManager,
    private val settings: AppSettings
) : ViewModel() {
    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            val base = connections.activeBaseUrl
            val token = connections.activeToken
            if (base == null || token.isNullOrBlank()) {
                _state.update { it.copy(status = "No active server") }
                return@launch
            }
            _state.update { it.copy(loading = true, status = "Loading hubs…") }
            try {
                val hubs = api.fetchHomeHubs(base, token)
                val libraries = try { api.fetchLibrarySections(base, token) } catch (_: Exception) { emptyList() }
                val filtered = settings.homeDisplay().filter(hubs, libraries)
                _state.update {
                    it.copy(
                        hubs = filtered,
                        loading = false,
                        status = if (filtered.isEmpty()) "No hubs" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Failed") }
            }
        }
    }

    class Factory(
        private val api: PlexApiClient,
        private val connections: ConnectionManager,
        private val settings: AppSettings
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            HomeViewModel(api, connections, settings) as T
    }
}
