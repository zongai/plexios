package com.plexclient.androidtv.playback

import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.net.URI

/**
 * Contract-aligned track descriptor (docs/cross-platform-playback-contract.md §6).
 * Maps to MediaTrack: id, type, language, title, codec, flags.
 */
data class PlayerTrack(
    val id: String,
    val groupIndex: Int,
    val trackIndex: Int,
    val label: String,
    val language: String? = null,
    val codec: String? = null,
    val type: Type,
    val selected: Boolean = false,
    val isDefault: Boolean = false,
    val isForced: Boolean = false,
    val isExternal: Boolean = false,
    val plexStreamId: Int? = null
) {
    enum class Type { Audio, Text, Video }

    val title: String get() = label
}


/**
 * Media3 / ExoPlayer shell with track enumeration and selection.
 */
class Media3PlayerShell(context: Context) : MediaPlayerContract {
    private val player: ExoPlayer = ExoPlayer.Builder(context).build()

    private val _state = MutableStateFlow(PlayerState.Idle)
    val state: StateFlow<PlayerState> = _state.asStateFlow()

    private val _audioTracks = MutableStateFlow<List<PlayerTrack>>(emptyList())
    val audioTracks: StateFlow<List<PlayerTrack>> = _audioTracks.asStateFlow()

    private val _subtitleTracks = MutableStateFlow<List<PlayerTrack>>(emptyList())
    val subtitleTracks: StateFlow<List<PlayerTrack>> = _subtitleTracks.asStateFlow()

    /**
     * Contract-aligned states (docs/cross-platform-playback-contract.md §4):
     * idle | loading | ready | buffering | playing | paused | ended | stopped | error
     *
     * ExoPlayer mapping:
     * - STATE_IDLE -> Idle (or Stopped after stop())
     * - STATE_BUFFERING -> Buffering (play intent unchanged; NOT paused)
     * - STATE_READY + isPlaying -> Playing
     * - STATE_READY + !playWhenReady -> Paused
     * - STATE_READY + playWhenReady && !isPlaying -> Ready
     * - STATE_ENDED -> Ended
     * - onPlayerError -> Error
     * - prepare/load -> Loading
     * - explicit stop() -> Stopped
     */
    enum class PlayerState { Idle, Loading, Ready, Buffering, Playing, Paused, Stopped, Ended, Error }

    val exoPlayer: ExoPlayer get() = player

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                _state.value = when (playbackState) {
                    Player.STATE_IDLE ->
                        if (_state.value == PlayerState.Stopped) PlayerState.Stopped else PlayerState.Idle
                    Player.STATE_BUFFERING -> PlayerState.Buffering
                    Player.STATE_READY -> when {
                        player.playWhenReady && player.isPlaying -> PlayerState.Playing
                        !player.playWhenReady -> PlayerState.Paused
                        else -> PlayerState.Ready
                    }
                    Player.STATE_ENDED -> PlayerState.Ended
                    else -> PlayerState.Idle
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                when {
                    isPlaying -> _state.value = PlayerState.Playing
                    player.playbackState == Player.STATE_READY && !player.playWhenReady ->
                        _state.value = PlayerState.Paused
                    player.playbackState == Player.STATE_READY ->
                        _state.value = PlayerState.Ready
                    player.playbackState == Player.STATE_ENDED ->
                        _state.value = PlayerState.Ended
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                _state.value = PlayerState.Error
            }

            override fun onTracksChanged(tracks: Tracks) {
                refreshTracks(tracks)
            }
        })
    }

    fun prepare(url: URI, startPositionMs: Long = 0) {
        val item = MediaItem.fromUri(url.toString())
        _state.value = PlayerState.Loading
        player.setMediaItem(item, startPositionMs)
        player.prepare()
    }

    fun play() {
        // play intent; buffering is not paused
        _state.value = if (player.playbackState == Player.STATE_BUFFERING) {
            PlayerState.Buffering
        } else {
            PlayerState.Playing
        }
        player.play()
    }

    fun pause() {
        player.pause()
        if (player.playbackState != Player.STATE_ENDED) {
            _state.value = PlayerState.Paused
        }
    }

    fun stop() {
        player.stop()
        _state.value = PlayerState.Stopped
    }

    fun seekTo(ms: Long) = player.seekTo(ms)

    /** Playback rate (1.0 = normal). */
    fun setRate(rate: Float) {
        player.setPlaybackSpeed(rate)
    }

    /** Linear volume 0…1 (player volume, not system stream volume). */
    fun setVolume(volume: Float) {
        player.volume = volume.coerceIn(0f, 1f)
    }

    fun selectAudio(track: PlayerTrack) {
        val groups = player.currentTracks.groups
        if (track.groupIndex !in groups.indices) return
        val group = groups[track.groupIndex]
        if (group.type != C.TRACK_TYPE_AUDIO) return
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setOverrideForType(
                TrackSelectionOverride(group.mediaTrackGroup, track.trackIndex)
            )
            .build()
    }

    fun selectSubtitle(track: PlayerTrack?) {
        if (track == null) {
            // Disable text tracks
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
            return
        }
        val groups = player.currentTracks.groups
        if (track.groupIndex !in groups.indices) return
        val group = groups[track.groupIndex]
        if (group.type != C.TRACK_TYPE_TEXT) return
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setOverrideForType(
                TrackSelectionOverride(group.mediaTrackGroup, track.trackIndex)
            )
            .build()
    }

    fun release() = player.release()

    private fun refreshTracks(tracks: Tracks) {
        val audio = mutableListOf<PlayerTrack>()
        val subs = mutableListOf<PlayerTrack>()
        tracks.groups.forEachIndexed { gi, group ->
            for (ti in 0 until group.length) {
                val format = group.getTrackFormat(ti)
                val label = format.label
                    ?: format.language
                    ?: "${group.type}-$ti"
                val selected = group.isTrackSelected(ti)
                when (group.type) {
                    C.TRACK_TYPE_AUDIO -> audio += PlayerTrack(
                        id = "a-$gi-$ti",
                        groupIndex = gi,
                        trackIndex = ti,
                        label = buildString {
                            append(label)
                            format.codecs?.let { append(" · $it") }
                            if (format.channelCount > 0) append(" · ${format.channelCount}ch")
                        },
                        language = format.language,
                        type = PlayerTrack.Type.Audio,
                        selected = selected
                    )
                    C.TRACK_TYPE_TEXT -> subs += PlayerTrack(
                        id = "s-$gi-$ti",
                        groupIndex = gi,
                        trackIndex = ti,
                        label = buildString {
                            append(label)
                            format.codecs?.let { append(" · $it") }
                        },
                        language = format.language,
                        type = PlayerTrack.Type.Text,
                        selected = selected
                    )
                }
            }
        }
        _audioTracks.value = audio
        _subtitleTracks.value = subs
    }
}
