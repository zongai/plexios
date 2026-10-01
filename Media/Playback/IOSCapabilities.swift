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
    /// True when matrix reflects MobileVLCKit Direct Play breadth.
    var isVLCProfile: Bool

    /// AVPlayer-only matrix (strict).
    static let current: IOSCapabilities = avPlayerProfile

    /// Probe hardware decode where possible (iOS 17+ deployment).
    static let avPlayerProfile: IOSCapabilities = {
        let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let av1: Bool = {
            let av01: CMVideoCodecType = 0x61307661 // 'av01'
            return VTIsHardwareDecodeSupported(av01)
        }()
        let vp9Native = false

        var video: Set<String> = [
            "h264", "avc", "avc1", "mpeg4", "mpeg2video", "mp4v"
        ]
        if hevc {
            video.formUnion(["hevc", "h265", "hev1", "hvc1"])
        }
        if av1 {
            video.formUnion(["av1", "av01"])
        }

        let containers: Set<String> = [
            "mp4", "m4v", "mov", "mpegts", "hls", "m3u8", "isom", "mp3", "aac"
        ]

        let audio: Set<String> = [
            "aac", "mp3", "ac3", "eac3", "eac3_atmos", "eac3-atmos",
            "flac", "alac", "pcm"
        ]

        return IOSCapabilities(
            supportedContainers: containers,
            supportedVideoCodecs: video,
            supportedAudioCodecs: audio,
            nativeSubtitleFormats: [
                "srt", "vtt", "webvtt", "mov_text", "tx3g", "text", "subrip", "utf-8", "utf8"
            ],
            maxAudioChannels: 8,
            supportsHEVC: hevc,
            supportsVP9: vp9Native,
            supportsAV1: av1,
            supportsHDR10: true,
            supportsDolbyVision: false,
            isVLCProfile: false
        )
    }()

    /// Broader Direct Play matrix when MobileVLCKit is the playback backend.
    static let vlcProfile: IOSCapabilities = {
        let base = avPlayerProfile
        var video = base.supportedVideoCodecs
        video.formUnion(["vp9", "vp09", "mpeg2video", "mpeg4", "wmv", "vc1", "msmpeg4"])
        var audio = base.supportedAudioCodecs
        audio.formUnion([
            "opus", "vorbis", "dca", "dts", "truehd", "mlp", "wmav2", "pcm_s16le"
        ])
        var containers = base.supportedContainers
        containers.formUnion([
            "mkv", "matroska", "webm", "avi", "wmv", "asf", "flv", "ts", "m2ts", "ogg", "ogm"
        ])
        var subs = base.nativeSubtitleFormats
        subs.formUnion(["ass", "ssa", "pgs", "vobsub", "dvd_subtitle", "hdmv_pgs_subtitle"])

        return IOSCapabilities(
            supportedContainers: containers,
            supportedVideoCodecs: video,
            supportedAudioCodecs: audio,
            nativeSubtitleFormats: subs,
            maxAudioChannels: 16,
            supportsHEVC: base.supportsHEVC,
            supportsVP9: true,
            supportsAV1: base.supportsAV1,
            supportsHDR10: true,
            supportsDolbyVision: false,
            isVLCProfile: true
        )
    }()

    /// Active matrix: VLC when linked + user allows it and is not forcing system player.
    static func active(preferences: PlaybackPreferences) -> IOSCapabilities {
        let wantVLC = preferences.allowVLCPlayer
            && !preferences.preferSystemPlayer
            && VLCPlaybackBackend.isLinked
        return wantVLC ? .vlcProfile : .avPlayerProfile
    }

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
        // VLC renders image + advanced text subs natively — no server burn-in.
        if isVLCProfile { return false }
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
        case .fit: return String(localized: "settings.aspect.fit")
        case .fill: return String(localized: "settings.aspect.fill")
        case .stretch: return String(localized: "settings.aspect.stretch")
        }
    }
}

/// Relative subtitle text size for VLC `freetype-rel-fontsize`
/// (smaller number → larger on-screen text).
enum SubtitleTextSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    /// VLC freetype-rel-fontsize value.
    var freetypeRelFontsize: Int {
        switch self {
        case .small: return 22
        case .medium: return 16
        case .large: return 12
        case .extraLarge: return 9
        }
    }

    var labelKey: String {
        switch self {
        case .small: return "settings.subtitle_size_small"
        case .medium: return "settings.subtitle_size_medium"
        case .large: return "settings.subtitle_size_large"
        case .extraLarge: return "settings.subtitle_size_xlarge"
        }
    }
}

struct PlaybackPreferences: Sendable {
    /// nil = original / auto
    var maxVideoBitrateKbps: Int?
    var autoPlayNextEpisode: Bool
    /// Ordered language preference (first match wins). Empty = auto/server default.
    var preferredAudioLanguages: [String]
    var preferredSubtitleLanguages: [String]
    var subtitlesEnabled: Bool
    /// On-screen subtitle text size (VLC freetype).
    var subtitleTextSize: SubtitleTextSize

    /// Convenience: first audio preference (legacy single-value access).
    var preferredAudioLanguage: String? { preferredAudioLanguages.first }
    var preferredSubtitleLanguage: String? { preferredSubtitleLanguages.first }
    /// Default rate when starting playback (1.0 = normal)
    var defaultPlaybackRate: Float
    var defaultAspectMode: VideoAspectMode
    /// Experimental native media engine (FFmpeg demux + VT / soft decode).
    var allowNativeMediaEngine: Bool
    /// Prefer MobileVLCKit for Direct Play (broader codecs/containers).
    var allowVLCPlayer: Bool
    /// Force AVPlayer path (better PiP / AirPlay Video) even when VLC is linked.
    var preferSystemPlayer: Bool

    static let `default` = PlaybackPreferences(
        maxVideoBitrateKbps: nil,
        autoPlayNextEpisode: true,
        preferredAudioLanguages: [],
        preferredSubtitleLanguages: [],
        subtitlesEnabled: true,
        subtitleTextSize: .medium,
        defaultPlaybackRate: 1.0,
        defaultAspectMode: .fit,
        allowNativeMediaEngine: false,
        allowVLCPlayer: true,
        preferSystemPlayer: false
    )

    static let rateOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// Common BCP-47 / ISO language codes used by Plex streams.
    /// Empty string = Auto (server / stream default).
    static let languageOptions: [(code: String, labelKey: String)] = [
        ("", "lang.auto"),
        ("en", "lang.en"),
        ("zh", "lang.zh"),
        ("zh-CN", "lang.zh_hans"),
        ("zh-TW", "lang.zh_hant"),
        ("ja", "lang.ja"),
        ("ko", "lang.ko"),
        ("es", "lang.es"),
        ("fr", "lang.fr"),
        ("de", "lang.de"),
        ("pt", "lang.pt"),
        ("ru", "lang.ru"),
        ("it", "lang.it"),
        ("ar", "lang.ar"),
        ("hi", "lang.hi"),
        ("th", "lang.th"),
        ("vi", "lang.vi"),
    ]
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
        static let subTextSize = "playback.subtitleTextSize"
        static let rate = "playback.defaultRate"
        static let aspect = "playback.aspectMode"
        static let nativeEngine = "playback.allowNativeMediaEngine"
        static let allowVLC = "playback.allowVLCPlayer"
        static let preferSystem = "playback.preferSystemPlayer"
        static let audioLang = "playback.audioLang"       // legacy single
        static let subLang = "playback.subLang"           // legacy single
        static let audioLangs = "playback.audioLangs"     // ordered list
        static let subLangs = "playback.subLangs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Ordered language preference list; migrates legacy single-string key if needed.
    private static func loadLangList(_ defaults: UserDefaults, listKey: String, legacyKey: String) -> [String] {
        if let list = defaults.stringArray(forKey: listKey), !list.isEmpty {
            return list
        }
        if let single = defaults.string(forKey: legacyKey), !single.isEmpty {
            return [single]
        }
        return []
    }

    var preferences: PlaybackPreferences {
        get {
            let bitrate = defaults.object(forKey: Keys.maxBitrate) as? Int
            return PlaybackPreferences(
                maxVideoBitrateKbps: bitrate,
                autoPlayNextEpisode: defaults.object(forKey: Keys.autoplay) as? Bool ?? true,
                preferredAudioLanguages: Self.loadLangList(defaults, listKey: Keys.audioLangs, legacyKey: Keys.audioLang),
                preferredSubtitleLanguages: Self.loadLangList(defaults, listKey: Keys.subLangs, legacyKey: Keys.subLang),
                subtitlesEnabled: defaults.object(forKey: Keys.subsEnabled) as? Bool ?? true,
                subtitleTextSize: SubtitleTextSize(rawValue: defaults.string(forKey: Keys.subTextSize) ?? "") ?? .medium,
                defaultPlaybackRate: defaults.object(forKey: Keys.rate) as? Float ?? 1.0,
                defaultAspectMode: VideoAspectMode(rawValue: defaults.string(forKey: Keys.aspect) ?? "") ?? .fit,
                allowNativeMediaEngine: defaults.object(forKey: Keys.nativeEngine) as? Bool ?? false,
                allowVLCPlayer: defaults.object(forKey: Keys.allowVLC) as? Bool ?? true,
                preferSystemPlayer: defaults.object(forKey: Keys.preferSystem) as? Bool ?? false
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
            defaults.set(newValue.subtitleTextSize.rawValue, forKey: Keys.subTextSize)
            defaults.set(newValue.defaultPlaybackRate, forKey: Keys.rate)
            defaults.set(newValue.defaultAspectMode.rawValue, forKey: Keys.aspect)
            defaults.set(newValue.allowNativeMediaEngine, forKey: Keys.nativeEngine)
            defaults.set(newValue.allowVLCPlayer, forKey: Keys.allowVLC)
            defaults.set(newValue.preferSystemPlayer, forKey: Keys.preferSystem)
            defaults.set(newValue.preferredAudioLanguages, forKey: Keys.audioLangs)
            defaults.set(newValue.preferredSubtitleLanguages, forKey: Keys.subLangs)
            // Keep legacy keys in sync for older builds
            if let a = newValue.preferredAudioLanguages.first {
                defaults.set(a, forKey: Keys.audioLang)
            } else {
                defaults.removeObject(forKey: Keys.audioLang)
            }
            if let s = newValue.preferredSubtitleLanguages.first {
                defaults.set(s, forKey: Keys.subLang)
            } else {
                defaults.removeObject(forKey: Keys.subLang)
            }
        }
    }
}
