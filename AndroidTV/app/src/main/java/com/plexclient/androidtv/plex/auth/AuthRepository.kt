package com.plexclient.androidtv.plex.auth

import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.identity.ClientIdentity
import com.plexclient.androidtv.plex.model.PlexPin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AuthRepository(
    private val api: PlexApiClient,
    private val store: SecureTokenStore,
    private val identity: ClientIdentity
) {
    private val _token = MutableStateFlow(store.authToken)
    val token: StateFlow<String?> = _token.asStateFlow()

    val isSignedIn: Boolean get() = !_token.value.isNullOrBlank()

    suspend fun createPin(): PlexPin = api.createPin()

    /**
     * Poll until claimed or [timeoutMs] elapses. Returns auth token or null.
     */
    suspend fun pollPin(pin: PlexPin, timeoutMs: Long = 300_000L, intervalMs: Long = 2_000L): String? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val updated = api.checkPin(pin.id, pin.code)
            val token = updated.authToken
            if (!token.isNullOrBlank()) {
                store.authToken = token
                _token.value = token
                return token
            }
            delay(intervalMs)
        }
        return null
    }

    fun signOut() {
        store.clear()
        _token.value = null
    }

    fun restoreFromStore() {
        _token.value = store.authToken
    }
}
