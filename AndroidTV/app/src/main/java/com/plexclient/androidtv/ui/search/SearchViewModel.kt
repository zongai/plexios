package com.plexclient.androidtv.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.model.PlexHub
import com.plexclient.androidtv.plex.server.ConnectionManager
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SearchUiState(
    val query: String = "",
    val hubs: List<PlexHub> = emptyList(),
    val status: String = "",
    val loading: Boolean = false
)

class SearchViewModel(
    private val api: PlexApiClient,
    private val connections: ConnectionManager
) : ViewModel() {
    private val _state = MutableStateFlow(SearchUiState())
    val state: StateFlow<SearchUiState> = _state.asStateFlow()
    private var job: Job? = null

    fun onQueryChange(q: String) {
        _state.update { it.copy(query = q) }
        job?.cancel()
        job = viewModelScope.launch {
            delay(300)
            search(q)
        }
    }

    fun search(q: String = _state.value.query) {
        viewModelScope.launch {
            val query = q.trim()
            if (query.isEmpty()) {
                _state.update { it.copy(hubs = emptyList(), status = "") }
                return@launch
            }
            val base = connections.activeBaseUrl
            val token = connections.activeToken
            if (base == null || token.isNullOrBlank()) {
                _state.update { it.copy(status = "No active server") }
                return@launch
            }
            _state.update { it.copy(loading = true, status = "") }
            try {
                val hubs = api.search(query, base, token)
                _state.update {
                    it.copy(
                        hubs = hubs,
                        loading = false,
                        status = if (hubs.all { h -> h.items.isEmpty() }) "No results" else ""
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, status = e.message ?: "Search failed") }
            }
        }
    }

    class Factory(
        private val api: PlexApiClient,
        private val connections: ConnectionManager
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            SearchViewModel(api, connections) as T
    }
}
