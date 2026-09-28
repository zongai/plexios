import Foundation
import VideoToolbox

/// Explicit capability matrix used by PlaybackDecisionEngine.
struct IOSCapabilities: Sendable {
    var supportedContainers: Set<String>
    var supportedVideoCodecs: Set<String>
    var supportedAudioCodecs: Set<String>
    var nativeSubtitleFormats: Set<String>
    var maxAudioChannels: Int
    var supportsHEVC: Bool
    var supportsVP9: Bool
    var supportsAV1: Bool
    var supportsHDR10: Bool
    var supportsDolbyVision: Bool

    /// Probe hardware decode where possible (iOS 17+ deployment).
    static let current: IOSCapabilities = {
        let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        // AV1 constant available on recent SDKs; fall back if missing.
        // AV1 fourcc 'av01' = 0x61307661; constant may be missing on older SDKs
        let av1: Bool = {
            let av01: CMVideoCodecType = 0x61307661 // 'av01'
            return VTIsHardwareDecodeSupported(av01)
        }()
        // VP9: AVPlayer on iOS does **not** reliably decode VP9 (WebM/MKV/fMP4).
        // Direct Play / Direct Stream would keep VP9 → black screen / failure.
        // Must transcode to H.264/HEVC on the server.
        let vp9Native = false

        var video: Set<String> = [
            "h264", "avc", "avc1", "mpeg4", "mpeg2video", "mp4v"
        ]
        if hevc {
            video.formUnion(["hevc", "h265", "hev1", "hvc1"])
        }
        // Do not add vp9/vp09 — forces PlaybackDecision → transcode
        if av1 {
            // Only when hardware reports support (A17+ / M-series class devices)
            video.formUnion(["av1", "av01"])
        }

        // Direct Play containers only (AVPlayer-native). MKV/WebM stay remux or transcode.
        let containers: Set<String> = [
            "mp4", "m4v", "mov", "mpegts", "hls", "m3u8", "isom", "mp3", "aac"
        ]

        // OPUS / Vorbis: not reliable in AVPlayer for progressive/Direct Play.
        // Leave them unsupported so decision engine requests server audio transcode
        // (or full transcode when paired with VP9).
        var audio: Set<String> = [
            "aac", "mp3", "ac3", "eac3", "eac3_atmos", "eac3-atmos",
            "flac", "alac", "pcm"
            // intentionally omit: opus, vorbis, dca/dts, truehd (transcode audio)
        ]

        return IOSCapabilities(
            supportedContainers: containers,
            supportedVideoCodecs: video,
            supportedAudioCodecs: audio,
            // Text tracks AVPlayer can render without burn-in
            nativeSubtitleFormats: [
                "srt", "vtt", "webvtt", "mov_text", "tx3g", "text", "subrip", "utf-8", "utf8"
            ],
            maxAudioChannels: 8,
            supportsHEVC: hevc,
            supportsVP9: vp9Native,
            supportsAV1: av1,
            supportsHDR10: true,
            supportsDolbyVision: false
        )
    }()

    /// Codecs the **server may deliver** in HLS after decision.
    /// Never advertise VP9 — PMS would pass through and AVPlayer still fails.
    var videoCodecsQueryValue: String {
        var list: [String] = ["h264"]
        if supportsHEVC { list.append("hevc") }
        if supportsAV1 { list.append("av1") }
        return list.joined(separator: ",")
    }

    var audioCodecsQueryValue: String {
        // Request AAC as primary so OPUS sources are transcoded
        "aac,mp3,ac3,eac3"
    }

    var subtitleCodecsQueryValue: String {
        "srt,vtt,http"
    }

    func supportsContainer(_ container: String?) -> Bool {
        guard let c = Self.normalizeContainer(container) else { return false }
        return supportedContainers.contains(c)
    }

    func supportsVideoCodec(_ codec: String?) -> Bool {
        guard let c = Self.normalizeVideoCodec(codec) else { return false }
        return supportedVideoCodecs.contains(c)
    }

    func supportsAudioCodec(_ codec: String?) -> Bool {
        guard let c = Self.normalizeAudioCodec(codec) else { return false }
        return supportedAudioCodecs.contains(c)
    }

    func supportsSubtitleNatively(_ stream: PlexStream) -> Bool {
        let format = Self.normalizeSubtitleFormat(stream.format ?? stream.codec) ?? ""
        if stream.isExternal {
            // External files need server packaging or side-load; treat text formats as soft-sub capable via remux
            return nativeSubtitleFormats.contains(format) || format.isEmpty
        }
        return nativeSubtitleFormats.contains(format)
    }

    func requiresBurnIn(_ stream: PlexStream) -> Bool {
        let format = Self.normalizeSubtitleFormat(stream.format ?? stream.codec) ?? ""
        let burnIn: Set<String> = [
            "pgs", "vobsub", "dvd_subtitle", "dvdsub", "hdmv_pgs_subtitle",
            "ass", "ssa", "image", "xsub"
        ]
        return burnIn.contains(format)
    }

    // MARK: - Normalization

    static func normalizeVideoCodec(_ raw: String?) -> String? {
        guard let r = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
            return nil
        }
        switch r {
        case "h264", "avc", "avc1", "x264": return "h264"
        case "hevc", "h265", "hev1", "hvc1", "x265": return "hevc"
        case "vp9", "vp09": return "vp9"
        case "av1", "av01": return "av1"
        case "mpeg4", "mp4v": return "mpeg4"
        case "mpeg2video", "mpeg2": return "mpeg2video"
        default: return r
        }
    }

    static func normalizeAudioCodec(_ raw: String?) -> String? {
        guard let r = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
            return nil
        }
        switch r {
        case "dca", "dts", "dts-hd", "dtshd": return "dca"
        case "eac3", "eac-3", "eac3_atmos", "eac3-atmos": return "eac3"
        case "mp3", "mp2": return "mp3"
        default: return r
        }
    }

    static func normalizeContainer(_ raw: String?) -> String? {
        guard let r = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
            return nil
        }
        switch r {
        case "matroska", "mkv": return "mkv"
        case "mpegts", "ts", "m2ts": return "mpegts"
        case "m3u8", "hls": return "hls"
        default: return r
        }
    }

    static func normalizeSubtitleFormat(_ raw: String?) -> String? {
        guard let r = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
            return nil
        }
        switch r {
        case "subrip", "srt": return "srt"
        case "webvtt", "vtt": return "vtt"
        case "mov_text", "tx3g", "text": return "mov_text"
        case "hdmv_pgs_subtitle", "pgs": return "pgs"
        case "dvd_subtitle", "dvdsub", "vobsub": return "vobsub"
        default: return r
        }
    }
}

// MARK: - Network class for decision

enum NetworkClass: String, Sendable {
    case lan
    case wan
    case relay
    case unknown
}

enum VideoAspectMode: String, Sendable, CaseIterable, Identifiable {
    case fit       // keep aspect ratio (letterbox) — default
    case fill      // fill screen (may crop)
    case stretch   // distort to fill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: return "Fit (default)"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }
}

struct PlaybackPreferences: Sendable {
    /// nil = original / auto
    var maxVideoBitrateKbps: Int?
    var autoPlayNextEpisode: Bool
    var preferredAudioLanguage: String?
    var preferredSubtitleLanguage: String?
    var subtitlesEnabled: Bool
    /// Default rate when starting playback (1.0 = normal)
    var defaultPlaybackRate: Float
    var defaultAspectMode: VideoAspectMode
    /// Experimental native media engine (FFmpeg demux + VT / soft decode).
    var allowNativeMediaEngine: Bool

    static let `default` = PlaybackPreferences(
        maxVideoBitrateKbps: nil,
        autoPlayNextEpisode: true,
        preferredAudioLanguage: nil,
        preferredSubtitleLanguage: nil,
        subtitlesEnabled: true,
        defaultPlaybackRate: 1.0,
        defaultAspectMode: .fit,
        allowNativeMediaEngine: false
    )

    static let rateOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
}

/// Persists user playback defaults (not secrets — UserDefaults is fine).
@MainActor
final class PlaybackSettingsStore {
    static let shared = PlaybackSettingsStore()

    private let defaults: UserDefaults
    private enum Keys {
        static let maxBitrate = "playback.maxBitrateKbps"
        static let autoplay = "playback.autoPlayNext"
        static let subsEnabled = "playback.subtitlesEnabled"
        static let rate = "playback.defaultRate"
        static let aspect = "playback.aspectMode"
        static let nativeEngine = "playback.allowNativeMediaEngine"
        static let audioLang = "playback.audioLang"
        static let subLang = "playback.subLang"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferences: PlaybackPreferences {
        get {
            let bitrate = defaults.object(forKey: Keys.maxBitrate) as? Int
            return PlaybackPreferences(
                maxVideoBitrateKbps: bitrate,
                autoPlayNextEpisode: defaults.object(forKey: Keys.autoplay) as? Bool ?? true,
                preferredAudioLanguage: defaults.string(forKey: Keys.audioLang),
                preferredSubtitleLanguage: defaults.string(forKey: Keys.subLang),
                subtitlesEnabled: defaults.object(forKey: Keys.subsEnabled) as? Bool ?? true,
                defaultPlaybackRate: defaults.object(forKey: Keys.rate) as? Float ?? 1.0,
                defaultAspectMode: VideoAspectMode(rawValue: defaults.string(forKey: Keys.aspect) ?? "") ?? .fit,
                allowNativeMediaEngine: defaults.object(forKey: Keys.nativeEngine) as? Bool ?? false
            )
        }
        set {
            if let br = newValue.maxVideoBitrateKbps {
                defaults.set(br, forKey: Keys.maxBitrate)
            } else {
                defaults.removeObject(forKey: Keys.maxBitrate)
            }
            defaults.set(newValue.autoPlayNextEpisode, forKey: Keys.autoplay)
            defaults.set(newValue.subtitlesEnabled, forKey: Keys.subsEnabled)
            defaults.set(newValue.defaultPlaybackRate, forKey: Keys.rate)
            defaults.set(newValue.defaultAspectMode.rawValue, forKey: Keys.aspect)
            defaults.set(newValue.allowNativeMediaEngine, forKey: Keys.nativeEngine)
            if let a = newValue.preferredAudioLanguage {
                defaults.set(a, forKey: Keys.audioLang)
            } else {
                defaults.removeObject(forKey: Keys.audioLang)
            }
            if let s = newValue.preferredSubtitleLanguage {
                defaults.set(s, forKey: Keys.subLang)
            } else {
                defaults.removeObject(forKey: Keys.subLang)
            }
        }
    }
}
