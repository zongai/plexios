import Foundation

/// Explicit capability matrix used by PlaybackDecisionEngine.
/// Keep conservative; widen only when validated on device.
struct IOSCapabilities: Sendable {
    var supportedContainers: Set<String>
    var supportedVideoCodecs: Set<String>
    var supportedAudioCodecs: Set<String>
    var nativeSubtitleFormats: Set<String>
    var maxAudioChannels: Int
    var supportsHEVC: Bool
    var supportsHDR10: Bool
    var supportsDolbyVision: Bool

    /// Baseline for modern iOS devices (iOS 17+).
    static let current: IOSCapabilities = {
        var video: Set<String> = ["h264", "avc", "mpeg4", "mpeg2video"]
        var audio: Set<String> = ["aac", "mp3", "ac3", "eac3", "eac3-atmos", "flac", "alac"]
        // HEVC is widely available on A10+; assume yes for iOS 17 deployment floor.
        let hevc = true
        if hevc {
            video.insert("hevc")
            video.insert("h265")
        }
        // AV1: only recent devices; leave off by default for safety.
        return IOSCapabilities(
            supportedContainers: ["mp4", "m4v", "mov", "mpegts", "hls"],
            supportedVideoCodecs: video,
            supportedAudioCodecs: audio,
            nativeSubtitleFormats: ["srt", "vtt", "webvtt", "mov_text", "tx3g"],
            maxAudioChannels: 8,
            supportsHEVC: hevc,
            supportsHDR10: true,
            supportsDolbyVision: false // device-dependent; keep false until probed
        )
    }()

    func supportsContainer(_ container: String?) -> Bool {
        guard let c = container?.lowercased() else { return false }
        return supportedContainers.contains(c)
    }

    func supportsVideoCodec(_ codec: String?) -> Bool {
        guard let c = codec?.lowercased() else { return false }
        return supportedVideoCodecs.contains(c)
    }

    func supportsAudioCodec(_ codec: String?) -> Bool {
        guard let c = codec?.lowercased() else { return false }
        return supportedAudioCodecs.contains(c)
    }

    func supportsSubtitleNatively(_ stream: PlexStream) -> Bool {
        let format = (stream.format ?? stream.codec)?.lowercased() ?? ""
        if stream.isExternal {
            return nativeSubtitleFormats.contains(format) || format.isEmpty
        }
        // Embedded text tracks
        return nativeSubtitleFormats.contains(format)
    }

    /// Image-based or complex subs that generally need burn-in.
    func requiresBurnIn(_ stream: PlexStream) -> Bool {
        let format = (stream.format ?? stream.codec)?.lowercased() ?? ""
        let burnIn = ["pgs", "vobsub", "dvd_subtitle", "hdmv_pgs_subtitle", "ass", "ssa"]
        return burnIn.contains(format)
    }
}

// MARK: - Network class for decision

enum NetworkClass: String, Sendable {
    case lan
    case wan
    case relay
    case unknown
}

struct PlaybackPreferences: Sendable {
    /// nil = original / auto
    var maxVideoBitrateKbps: Int?
    var autoPlayNextEpisode: Bool
    var preferredAudioLanguage: String?
    var preferredSubtitleLanguage: String?
    var subtitlesEnabled: Bool

    static let `default` = PlaybackPreferences(
        maxVideoBitrateKbps: nil,
        autoPlayNextEpisode: true,
        preferredAudioLanguage: nil,
        preferredSubtitleLanguage: nil,
        subtitlesEnabled: true
    )
}
