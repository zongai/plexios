package com.plexclient.androidtv.playback

import java.net.URI

/**
 * Cross-platform playback contract for Android TV.
 * See docs/cross-platform-playback-contract.md.
 *
 * Implemented by [Media3PlayerShell] (ExoPlayer). LibVLC adapter is deferred.
 */
interface MediaPlayerContract {
    val state: kotlinx.coroutines.flow.StateFlow<Media3PlayerShell.PlayerState>
    val audioTracks: kotlinx.coroutines.flow.StateFlow<List<PlayerTrack>>
    val subtitleTracks: kotlinx.coroutines.flow.StateFlow<List<PlayerTrack>>

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
