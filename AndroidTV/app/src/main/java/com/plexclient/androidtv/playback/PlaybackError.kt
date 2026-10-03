package com.plexclient.androidtv.playback

/**
 * Cross-platform playback error (docs/cross-platform-playback-contract.md §8).
 * Codes must stay aligned with iOS PlaybackErrorCode / Windows PlaybackErrorCode.
 */
enum class PlaybackErrorCode {
    Network,
    MediaUnavailable,
    Decode,
    Unsupported,
    Subtitle,
    Cancelled,
    Session,
    Backend,
    Track,
    Unknown;

    val wire: String
        get() = when (this) {
            Network -> "network"
            MediaUnavailable -> "mediaUnavailable"
            Decode -> "decode"
            Unsupported -> "unsupported"
            Subtitle -> "subtitle"
            Cancelled -> "cancelled"
            Session -> "session"
            Backend -> "backend"
            Track -> "track"
            Unknown -> "unknown"
        }
}

enum class PlaybackSuggestedAction {
    Retry, SwitchBackend, Transcode, None
}

data class PlaybackError(
    val code: PlaybackErrorCode,
    val message: String,
    val recoverable: Boolean = code != PlaybackErrorCode.Cancelled
        && code != PlaybackErrorCode.Unsupported
        && code != PlaybackErrorCode.MediaUnavailable,
    val suggestedAction: PlaybackSuggestedAction = defaultAction(code),
    val cause: Throwable? = null
) {
    companion object {
        private fun defaultAction(code: PlaybackErrorCode): PlaybackSuggestedAction = when (code) {
            PlaybackErrorCode.Network, PlaybackErrorCode.Session -> PlaybackSuggestedAction.Retry
            PlaybackErrorCode.Decode, PlaybackErrorCode.Backend -> PlaybackSuggestedAction.SwitchBackend
            PlaybackErrorCode.Unsupported -> PlaybackSuggestedAction.Transcode
            PlaybackErrorCode.Subtitle, PlaybackErrorCode.Track -> PlaybackSuggestedAction.Retry
            else -> PlaybackSuggestedAction.None
        }

        fun fromThrowable(t: Throwable, fallback: PlaybackErrorCode = PlaybackErrorCode.Unknown): PlaybackError {
            val msg = t.message?.takeIf { it.isNotBlank() } ?: t.javaClass.simpleName
            val code = when {
                t is java.io.IOException || msg.contains("Unable to connect", true)
                    || msg.contains("network", true) -> PlaybackErrorCode.Network
                msg.contains("404") || msg.contains("not available", true) ->
                    PlaybackErrorCode.MediaUnavailable
                msg.contains("Subtitle", true) || msg.contains("SPU", true) ->
                    PlaybackErrorCode.Subtitle
                msg.contains("Unsupported", true) || msg.contains("codec", true) ->
                    PlaybackErrorCode.Unsupported
                msg.contains("cancel", true) -> PlaybackErrorCode.Cancelled
                else -> fallback
            }
            return PlaybackError(code = code, message = msg, cause = t)
        }

        fun decode(message: String) = PlaybackError(PlaybackErrorCode.Decode, message)
        fun session(message: String) = PlaybackError(PlaybackErrorCode.Session, message)
        fun network(message: String) = PlaybackError(PlaybackErrorCode.Network, message)
    }
}
