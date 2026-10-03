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

data class PlayerTrack(
    val id: String,
    val groupIndex: Int,
    val trackIndex: Int,
    val label: String,
    val language: String?,
    val type: Type,
    val selected: Boolean
) {
    enum class Type { Audio, Text }
}

/**
 * Media3 / ExoPlayer shell with track enumeration and selection.
 */
class Media3PlayerShell(context: Context) {
    private val player: ExoPlayer = ExoPlayer.Builder(context).build()

    private val _state = MutableStateFlow(PlayerState.Idle)
    val state: StateFlow<PlayerState> = _state.asStateFlow()

    private val _audioTracks = MutableStateFlow<List<PlayerTrack>>(emptyList())
    val audioTracks: StateFlow<List<PlayerTrack>> = _audioTracks.asStateFlow()

    private val _subtitleTracks = MutableStateFlow<List<PlayerTrack>>(emptyList())
    val subtitleTracks: StateFlow<List<PlayerTrack>> = _subtitleTracks.asStateFlow()

    enum class PlayerState { Idle, Buffering, Ready, Playing, Ended, Error }

    val exoPlayer: ExoPlayer get() = player

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                _state.value = when (playbackState) {
                    Player.STATE_BUFFERING -> PlayerState.Buffering
                    Player.STATE_READY -> if (player.isPlaying) PlayerState.Playing else PlayerState.Ready
                    Player.STATE_ENDED -> PlayerState.Ended
                    else -> PlayerState.Idle
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) _state.value = PlayerState.Playing
                else if (player.playbackState == Player.STATE_READY) _state.value = PlayerState.Ready
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
        player.setMediaItem(item, startPositionMs)
        player.prepare()
    }

    fun play() = player.play()
    fun pause() = player.pause()
    fun seekTo(ms: Long) = player.seekTo(ms)

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
