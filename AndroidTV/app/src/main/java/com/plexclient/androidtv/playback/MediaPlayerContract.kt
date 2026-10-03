package com.plexclient.androidtv.playback

import java.net.URI
import kotlinx.coroutines.flow.StateFlow

/**
 * Cross-platform playback contract for Android TV.
 * See docs/cross-platform-playback-contract.md.
 *
 * Implemented by [Media3PlayerShell] (ExoPlayer). LibVLC adapter is deferred.
 * UI/ViewModel should depend on this interface, not on ExoPlayer APIs,
 * except a single surface-bind helper for PlayerView.
 */
interface MediaPlayerContract {
    val state: StateFlow<PlayerState>
    val audioTracks: StateFlow<List<PlayerTrack>>
    val subtitleTracks: StateFlow<List<PlayerTrack>>

    /** Contract §5 — milliseconds. */
    val positionMs: Long
    val durationMs: Long
    val isPlaying: Boolean
    val isBuffering: Boolean

    fun prepare(url: URI, startPositionMs: Long = 0)
    fun play()
    fun pause()
    fun stop()
    fun seekTo(ms: Long)
    fun setRate(rate: Float)
    fun setVolume(volume: Float)
    fun selectAudio(track: PlayerTrack)
    fun selectSubtitle(track: PlayerTrack?)
    fun release()
}

/**
 * Contract-aligned player states (docs §4).
 * Hoisted out of Media3PlayerShell so the contract does not depend on the shell type.
 */
enum class PlayerState {
    Idle, Loading, Ready, Buffering, Playing, Paused, Stopped, Ended, Error
}
