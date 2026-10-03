package com.plexclient.androidtv.playback

import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.model.PlexStream

enum class PlaybackMode { DirectPlay, DirectStream, Transcode }

/** Contract: system (ExoPlayer) vs vlc fallback. */
enum class PlaybackBackend { System, Vlc }

enum class NetworkClass { Local, Remote, Relay }

data class ClientCapabilities(
    val supportedContainers: Set<String>,
    val supportedVideoCodecs: Set<String>,
    val supportedAudioCodecs: Set<String>,
    val supportedSubtitleFormats: Set<String>,
    val maxVideoWidth: Int,
    val maxVideoHeight: Int,
    val maxAudioChannels: Int,
    val supportsHDR10: Boolean,
    val supportsDolbyVision: Boolean,
    val supportsDirectPlay: Boolean,
    val supportsDirectStream: Boolean,
    val supportsTranscode: Boolean,
    val supportsHLS: Boolean,
    val canRenderTextSubtitles: Boolean,
    val canRenderBitmapSubtitles: Boolean,
    val requiresBurnInFor: Set<String>
) {
    companion object {
        /** Conservative Media3 / ExoPlayer capability matrix for Android TV. */
        val AndroidTVDefault = ClientCapabilities(
            supportedContainers = setOf("mp4", "mkv", "mov", "m4v", "webm", "mpegts", "avi"),
            supportedVideoCodecs = setOf("h264", "hevc", "vp9", "av1", "mpeg4", "mpeg2video"),
            supportedAudioCodecs = setOf("aac", "ac3", "eac3", "mp3", "flac", "opus", "vorbis", "dts"),
            supportedSubtitleFormats = setOf("srt", "ass", "ssa", "vtt", "subrip"),
            maxVideoWidth = 3840,
            maxVideoHeight = 2160,
            maxAudioChannels = 8,
            supportsHDR10 = true,
            supportsDolbyVision = false,
            supportsDirectPlay = true,
            supportsDirectStream = true,
            supportsTranscode = true,
            supportsHLS = true,
            canRenderTextSubtitles = true,
            canRenderBitmapSubtitles = false,
            requiresBurnInFor = setOf("pgs", "vobsub", "dvd")
        )
    }
}

data class PlaybackDecision(
    val mode: PlaybackMode,
    val reason: String,
    /** Contract: system (ExoPlayer) vs vlc fallback. */
    val backend: PlaybackBackend = PlaybackBackend.System,
    val mediaIndex: Int = 0,
    val partIndex: Int = 0,
    val selectedAudioStreamId: Int? = null,
    val selectedSubtitleStreamId: Int? = null,
    val burnInSubtitles: Boolean = false,
    val videoBitrate: Int? = null
)

data class PlaybackPreferences(
    val autoPlayNextEpisode: Boolean = true,
    val subtitlesEnabled: Boolean = true,
    val preferredAudioLanguages: List<String> = emptyList(),
    val preferredSubtitleLanguages: List<String> = emptyList(),
    val maxRemoteBitrate: Int = 20_000_000
) {
    val preferredAudioLanguage: String? get() = preferredAudioLanguages.firstOrNull()
    val preferredSubtitleLanguage: String? get() = preferredSubtitleLanguages.firstOrNull()
    companion object {
        val Default = PlaybackPreferences()
    }
}

/**
 * Port of iOS / Windows PlaybackDecisionEngine semantics for Android TV / Media3.
 */
class PlaybackDecisionEngine(
    private val caps: ClientCapabilities = ClientCapabilities.AndroidTVDefault,
    private val prefs: PlaybackPreferences = PlaybackPreferences.Default
) {
    fun decide(metadata: PlexMetadata, network: NetworkClass = NetworkClass.Local): PlaybackDecision {
        val media = metadata.media.firstOrNull()
            ?: return PlaybackDecision(PlaybackMode.Transcode, "No media element")
        val part = media.parts.firstOrNull()
            ?: return PlaybackDecision(PlaybackMode.Transcode, "No part")

        val container = (media.container ?: part.container ?: "").lowercase()
        val videoCodec = (media.videoCodec ?: "").lowercase()
        val audioStreams = part.streams.filter { it.streamType == PlexStream.StreamType.Audio }
        val subtitleStreams = part.streams.filter { it.streamType == PlexStream.StreamType.Subtitle }

        val audioId = selectAudio(audioStreams)
        val selectedAudio = audioStreams.firstOrNull { it.id == audioId }
        val audioCodec = (selectedAudio?.codec ?: media.audioCodec ?: "").lowercase()
        val (subtitleId, burnIn) = selectSubtitle(subtitleStreams)

        if (burnIn) {
            return PlaybackDecision(
                mode = PlaybackMode.Transcode,
                reason = "Subtitle requires burn-in",
                selectedAudioStreamId = audioId,
                selectedSubtitleStreamId = subtitleId,
                burnInSubtitles = true,
                videoBitrate = bitrateFor(network)
            )
        }

        val containerOk = container.isEmpty() || container in caps.supportedContainers
        val videoOk = videoCodec.isEmpty() || videoCodec in caps.supportedVideoCodecs
        val audioOk = audioCodec.isEmpty() || audioCodec in caps.supportedAudioCodecs

        if (caps.supportsDirectPlay && containerOk && videoOk && audioOk) {
            return PlaybackDecision(
                mode = PlaybackMode.DirectPlay,
                reason = "Container=$container video=$videoCodec audio=$audioCodec supported",
                selectedAudioStreamId = audioId,
                selectedSubtitleStreamId = subtitleId
            )
        }

        if (caps.supportsDirectStream && videoOk) {
            return PlaybackDecision(
                mode = PlaybackMode.DirectStream,
                reason = "Remux: video ok ($videoCodec), container/audio needs remux",
                selectedAudioStreamId = audioId,
                selectedSubtitleStreamId = subtitleId
            )
        }

        return PlaybackDecision(
            mode = PlaybackMode.Transcode,
            reason = "Unsupported: container=$container video=$videoCodec audio=$audioCodec",
            selectedAudioStreamId = audioId,
            selectedSubtitleStreamId = subtitleId,
            burnInSubtitles = burnIn,
            videoBitrate = bitrateFor(network)
        )
    }

    private fun selectAudio(streams: List<PlexStream>): Int? {
        for (pref in prefs.preferredAudioLanguages) {
            streams.firstOrNull { matchesLanguage(it, pref) }?.let { return it.id }
        }
        return streams.firstOrNull { it.selected }?.id
            ?: streams.firstOrNull()?.id
    }

    private fun selectSubtitle(streams: List<PlexStream>): Pair<Int?, Boolean> {
        if (!prefs.subtitlesEnabled) return null to false
        for (pref in prefs.preferredSubtitleLanguages) {
            streams.firstOrNull { matchesLanguage(it, pref) }?.let {
                return it.id to requiresBurnIn(it)
            }
        }
        val selected = streams.firstOrNull { it.selected }
        if (selected != null) return selected.id to requiresBurnIn(selected)
        return null to false
    }

    private fun matchesLanguage(stream: PlexStream, pref: String): Boolean {
        val p = pref.trim().lowercase()
        if (p.isEmpty()) return false
        val code = (stream.languageCode ?: "").lowercase()
        val lang = (stream.language ?: "").lowercase()
        if (code == p || code.startsWith("$p-") || p.startsWith("$code-")) return true
        if (lang.startsWith(p)) return true
        if (p == "zh" && (code.startsWith("zh") || "chinese" in lang || "中文" in lang)) return true
        return false
    }

    private fun requiresBurnIn(s: PlexStream): Boolean {
        val fmt = (s.codec ?: s.format ?: "").lowercase()
        return fmt in caps.requiresBurnInFor
    }

    private fun bitrateFor(network: NetworkClass): Int = when (network) {
        NetworkClass.Local -> 40_000_000
        NetworkClass.Remote -> prefs.maxRemoteBitrate
        NetworkClass.Relay -> 4_000_000
    }
}
