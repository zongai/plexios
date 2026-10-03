package com.plexclient.androidtv.playback

import com.plexclient.androidtv.plex.identity.ClientIdentity
import com.plexclient.androidtv.plex.model.PlexMetadata
import com.plexclient.androidtv.plex.model.ServerContext
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class PlaybackUrlBuilder(private val identity: ClientIdentity) {
    fun build(context: ServerContext, metadata: PlexMetadata, decision: PlaybackDecision): URI {
        val media = metadata.media.getOrNull(decision.mediaIndex)
            ?: error("mediaIndex out of range")
        val part = media.parts.getOrNull(decision.partIndex)
            ?: error("partIndex out of range")

        val base = context.baseUrl.toString().trimEnd('/')
        val token = context.token

        return when (decision.mode) {
            PlaybackMode.DirectPlay -> {
                val key = part.key.trimStart('/')
                URI("$base/$key?X-Plex-Token=${enc(token)}")
            }
            PlaybackMode.DirectStream -> {
                // Universal transcoder with copy video / remux
                val path = buildString {
                    append("$base/video/:/transcode/universal/start.m3u8?")
                    append("path=${enc(metadata.key)}")
                    append("&mediaIndex=${decision.mediaIndex}")
                    append("&partIndex=${decision.partIndex}")
                    append("&protocol=hls")
                    append("&directPlay=0&directStream=1&subtitleSize=100")
                    append("&X-Plex-Token=${enc(token)}")
                    append("&X-Plex-Client-Identifier=${enc(identity.clientIdentifier)}")
                    append("&X-Plex-Product=${enc(identity.product)}")
                    append("&X-Plex-Platform=${enc(identity.platform)}")
                }
                URI(path)
            }
            PlaybackMode.Transcode -> {
                val bitrate = decision.videoBitrate ?: 8_000_000
                val path = buildString {
                    append("$base/video/:/transcode/universal/start.m3u8?")
                    append("path=${enc(metadata.key)}")
                    append("&mediaIndex=${decision.mediaIndex}")
                    append("&partIndex=${decision.partIndex}")
                    append("&protocol=hls")
                    append("&directPlay=0&directStream=0")
                    append("&videoQuality=100&videoBitrate=${bitrate / 1000}")
                    append("&subtitleSize=100")
                    if (decision.burnInSubtitles) append("&subtitles=burn")
                    decision.selectedSubtitleStreamId?.let { append("&subtitleStreamID=$it") }
                    decision.selectedAudioStreamId?.let { append("&audioStreamID=$it") }
                    append("&X-Plex-Token=${enc(token)}")
                    append("&X-Plex-Client-Identifier=${enc(identity.clientIdentifier)}")
                    append("&X-Plex-Product=${enc(identity.product)}")
                    append("&X-Plex-Platform=${enc(identity.platform)}")
                }
                URI(path)
            }
        }
    }

    private fun enc(s: String) = URLEncoder.encode(s, StandardCharsets.UTF_8)
}
