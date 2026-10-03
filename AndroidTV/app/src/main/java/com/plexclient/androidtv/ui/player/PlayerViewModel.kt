package com.plexclient.androidtv.ui.player

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.media3.common.Player
import com.plexclient.androidtv.playback.Media3PlayerShell
import com.plexclient.androidtv.playback.NextEpisodeResolver
import com.plexclient.androidtv.playback.PlaybackDecisionEngine
import com.plexclient.androidtv.playback.PlaybackPreferences
import com.plexclient.androidtv.playback.PlaybackRequest
import com.plexclient.androidtv.playback.PlaybackUrlBuilder
import com.plexclient.androidtv.playback.PlayerTrack
import com.plexclient.androidtv.playback.TimelineReporter
import com.plexclient.androidtv.plex.api.PlexApiClient
import com.plexclient.androidtv.plex.model.PlexMetadataType
import com.plexclient.androidtv.settings.AppSettings
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class PlayerUiState(
    val title: String = "",
    val modeLabel: String = "",
    val status: String = "",
    val backend: String = "Media3",
    val audioTracks: List<PlayerTrack> = emptyList(),
    val subtitleTracks: List<PlayerTrack> = emptyList(),
    val showTrackPanel: Boolean = false,
    val showSkipMarker: Boolean = false,
    val skipMarkerLabel: String = "Skip Intro"
)

class PlayerViewModel(
    app: Application,
    private val api: PlexApiClient,
    private val decisionEngine: PlaybackDecisionEngine,
    private val urlBuilder: PlaybackUrlBuilder,
    private val timeline: TimelineReporter,
    private val appSettings: AppSettings
) : AndroidViewModel(app) {
    /** Media3 surface only — prefer contract methods for control/progress. */
    fun playerForView(): androidx.media3.exoplayer.ExoPlayer = shell.exoPlayer

    val shell = Media3PlayerShell(app.applicationContext)

    private val prefs: PlaybackPreferences
        get() = PlaybackPreferences(
            autoPlayNextEpisode = appSettings.autoPlayNextEpisode,
            subtitlesEnabled = appSettings.subtitlesEnabled,
            preferredAudioLanguages = listOfNotNull(appSettings.preferredAudioLanguage),
            preferredSubtitleLanguages = listOfNotNull(appSettings.preferredSubtitleLanguage),
            maxRemoteBitrate = appSettings.maxRemoteBitrate
        )

    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state.asStateFlow()

    private var current: PlaybackRequest? = null
    private var markers: List<com.plexclient.androidtv.plex.model.PlexMarker> = emptyList()
    private var skipToMs: Long = 0
    private var positionJob: Job? = null
    private var reportJob: Job? = null

    init {
        shell.exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) {
                    viewModelScope.launch { onEnded() }
                }
            }
        })
        viewModelScope.launch {
            shell.audioTracks.collect { list ->
                _state.update { it.copy(audioTracks = list) }
            }
        }
        viewModelScope.launch {
            shell.subtitleTracks.collect { list ->
                _state.update { it.copy(subtitleTracks = list) }
            }
        }
    }

    fun play(request: PlaybackRequest) {
        current = request
        markers = request.metadata.markers
        viewModelScope.launch {
            _state.update {
                it.copy(
                    title = request.metadata.title,
                    modeLabel = request.decision.mode.name,
                    status = request.decision.reason
                )
            }
            try {
                shell.prepare(request.mediaUrl, request.startPositionMs)
                shell.play()
                _state.update { it.copy(status = "Playing") }
                startTimelineLoop()
                startPositionWatch()
                timeline.report(
                    request.context,
                    request.metadata.ratingKey,
                    request.startPositionMs,
                    request.metadata.duration ?: 0,
                    "playing"
                )
            } catch (e: Exception) {
                _state.update { it.copy(status = e.message ?: "Playback error") }
            }
        }
    }

    fun togglePlayPause() {
        val req = current
        if (shell.isPlaying) {
            shell.pause()
            if (req != null) {
                timeline.report(
                    req.context,
                    req.metadata.ratingKey,
                    shell.positionMs,
                    shell.durationMs.takeIf { it > 0 } ?: (req.metadata.duration ?: 0),
                    "paused"
                )
            }
            _state.update { it.copy(status = "Paused") }
        } else {
            shell.play()
            if (req != null) {
                timeline.report(
                    req.context,
                    req.metadata.ratingKey,
                    shell.positionMs,
                    shell.durationMs.takeIf { it > 0 } ?: (req.metadata.duration ?: 0),
                    "playing"
                )
            }
            _state.update { it.copy(status = "Playing") }
        }
    }

    fun stopPlayback() {
        val req = current
        if (req != null) {
            timeline.report(
                req.context,
                req.metadata.ratingKey,
                shell.positionMs,
                shell.durationMs.takeIf { it > 0 } ?: (req.metadata.duration ?: 0),
                "stopped"
            )
        }
        shell.stop()
        reportJob?.cancel()
        positionJob?.cancel()
        _state.update { it.copy(status = "Stopped") }
    }

    fun toggleTrackPanel() {
        _state.update { it.copy(showTrackPanel = !it.showTrackPanel) }
    }

    fun selectAudio(track: PlayerTrack) {
        shell.selectAudio(track)
        _state.update { it.copy(status = "Audio: ${track.label}") }
    }

    fun selectSubtitle(track: PlayerTrack?) {
        shell.selectSubtitle(track)
        _state.update {
            it.copy(status = if (track == null) "Subtitles off" else "Sub: ${track.label}")
        }
    }


    private fun startPositionWatch() {
        positionJob?.cancel()
        positionJob = viewModelScope.launch {
            while (isActive) {
                delay(500)
                updateSkipMarker()
            }
        }
    }

    private fun updateSkipMarker() {
        val pos = shell.positionMs
        val active = markers.firstOrNull {
            it.type == com.plexclient.androidtv.plex.model.PlexMarkerType.Intro ||
                it.type == com.plexclient.androidtv.plex.model.PlexMarkerType.Credits
        }?.takeIf { it.contains(pos) }
        // prefer currently containing
        val hit = markers.firstOrNull {
            (it.type == com.plexclient.androidtv.plex.model.PlexMarkerType.Intro ||
                it.type == com.plexclient.androidtv.plex.model.PlexMarkerType.Credits) && it.contains(pos)
        }
        if (hit == null) {
            _state.update { it.copy(showSkipMarker = false) }
            return
        }
        skipToMs = hit.endTimeOffset
        val label = if (hit.type == com.plexclient.androidtv.plex.model.PlexMarkerType.Intro) "Skip Intro" else "Skip Credits"
        _state.update { it.copy(showSkipMarker = true, skipMarkerLabel = label) }
    }

    fun skipMarker() {
        if (skipToMs <= 0) return
        shell.seekTo(skipToMs)
        _state.update { it.copy(showSkipMarker = false) }
    }

    private fun startTimelineLoop() {
        reportJob?.cancel()
        reportJob = viewModelScope.launch {
            while (isActive) {
                delay(15_000)
                val req = current ?: continue
                val pos = shell.positionMs
                val dur = shell.durationMs.takeIf { it > 0 } ?: (req.metadata.duration ?: 0)
                val st = when {
                    shell.isPlaying -> "playing"
                    shell.isBuffering -> "buffering"
                    else -> "paused"
                }
                timeline.report(req.context, req.metadata.ratingKey, pos, dur, st)
            }
        }
    }

    private suspend fun onEnded() {
        val req = current ?: return
        timeline.report(
            req.context,
            req.metadata.ratingKey,
            req.metadata.duration ?: 0,
            req.metadata.duration ?: 0,
            "stopped"
        )
        if (!prefs.autoPlayNextEpisode) return
        if (req.metadata.type != PlexMetadataType.Episode) {
            _state.update { it.copy(status = "Playback finished") }
            return
        }
        try {
            _state.update { it.copy(status = "Loading next episode…") }
            val next = NextEpisodeResolver.findNext(api, req.context, req.metadata)
            if (next == null) {
                _state.update { it.copy(status = "Playback finished") }
                return
            }
            val decision = decisionEngine.decide(next, req.network)
            val url = urlBuilder.build(req.context, next, decision)
            play(
                PlaybackRequest(
                    metadata = next,
                    context = req.context,
                    network = req.network,
                    decision = decision,
                    mediaUrl = url,
                    startPositionMs = 0
                )
            )
        } catch (e: Exception) {
            _state.update { it.copy(status = "Next episode failed: ${e.message}") }
        }
    }

    fun release() {
        reportJob?.cancel()
        current?.let { req ->
            timeline.report(
                req.context,
                req.metadata.ratingKey,
                shell.positionMs,
                shell.durationMs.takeIf { it > 0 } ?: (req.metadata.duration ?: 0),
                "stopped"
            )
        }
        shell.release()
    }

    class Factory(
        private val app: Application,
        private val api: PlexApiClient,
        private val decisionEngine: PlaybackDecisionEngine,
        private val urlBuilder: PlaybackUrlBuilder,
        private val timeline: TimelineReporter,
        private val appSettings: AppSettings
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            PlayerViewModel(app, api, decisionEngine, urlBuilder, timeline, appSettings) as T
    }
}
