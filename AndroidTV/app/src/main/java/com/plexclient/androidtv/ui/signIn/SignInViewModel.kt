package com.plexclient.androidtv.ui.signIn

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.plexclient.androidtv.plex.auth.AuthRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SignInUiState(
    val pinCode: String? = null,
    val status: String = "",
    val signedIn: Boolean = false
)

class SignInViewModel(
    private val auth: AuthRepository
) : ViewModel() {
    private val _state = MutableStateFlow(SignInUiState(signedIn = auth.isSignedIn))
    val state: StateFlow<SignInUiState> = _state.asStateFlow()

    fun startPinFlow() {
        if (auth.isSignedIn) {
            _state.update { it.copy(signedIn = true) }
            return
        }
        viewModelScope.launch {
            try {
                _state.update { it.copy(status = "Requesting PIN…") }
                val pin = auth.createPin()
                _state.update { it.copy(pinCode = pin.code, status = "Waiting for authorization…") }
                val token = auth.pollPin(pin)
                if (token != null) {
                    _state.update { it.copy(signedIn = true, status = "Signed in") }
                } else {
                    _state.update { it.copy(status = "PIN expired. Restart the app to try again.") }
                }
            } catch (e: Exception) {
                _state.update { it.copy(status = e.message ?: "Sign-in failed") }
            }
        }
    }

    class Factory(private val auth: AuthRepository) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = SignInViewModel(auth) as T
    }
}
