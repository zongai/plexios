package com.plexclient.androidtv.ui.signIn

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import java.util.concurrent.atomic.AtomicBoolean

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SignInScreen(
    viewModel: SignInViewModel,
    onSignedIn: () -> Unit
) {
    val state by viewModel.state.collectAsState()
    // Prevent double navigation if recomposition fires signedIn twice
    val navigated = remember { AtomicBoolean(false) }

    LaunchedEffect(Unit) {
        viewModel.startPinFlow()
    }
    LaunchedEffect(state.signedIn) {
        if (state.signedIn && navigated.compareAndSet(false, true)) {
            onSignedIn()
        }
    }

    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier.padding(horizontal = 64.dp)
        ) {
            Text(
                text = "Sign in to Plex",
                style = MaterialTheme.typography.headlineLarge,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                text = "On any device open plex.tv/link and enter this code",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Text(
                text = state.pinCode ?: "····",
                style = MaterialTheme.typography.displayMedium,
                color = MaterialTheme.colorScheme.primary
            )
            if (state.status.isNotBlank()) {
                Text(
                    text = state.status,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
