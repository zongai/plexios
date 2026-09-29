import Foundation

// MARK: - Playlist

struct IPTVPlaylist: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var urlString: String
    var enabled: Bool
    var lastUpdated: Date?
    var channelCount: Int
    var epgURLString: String?
    var autoRefreshHours: Int // 0 = manual only

    var url: URL? { IPTVNetwork.normalizeURL(from: urlString) }
    var epgURL: URL? { epgURLString.flatMap { IPTVNetwork.normalizeURL(from: $0) } }

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        enabled: Bool = true,
        lastUpdated: Date? = nil,
        channelCount: Int = 0,
        epgURLString: String? = nil,
        autoRefreshHours: Int = 12
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.enabled = enabled
        self.lastUpdated = lastUpdated
        self.channelCount = channelCount
        self.epgURLString = epgURLString
        self.autoRefreshHours = autoRefreshHours
    }
}

// MARK: - Source

enum IPTVStreamProtocol: String, Codable, Sendable {
    case hls
    case http
    case https
    case mpegts
    case unknown
}

enum IPTVStreamQuality: String, Codable, CaseIterable, Sendable {
    case unknown
    case lowest
    case sd // ~480p
    case hd // ~720p
    case fullHD // ~1080p
    case uhd
    case highest

    var sortRank: Int {
        switch self {
        case .unknown: return 0
        case .lowest: return 1
        case .sd: return 2
        case .hd: return 3
        case .fullHD: return 4
        case .uhd: return 5
        case .highest: return 6
        }
    }

    var displayName: String {
        switch self {
        case .unknown: return String(localized: "iptv.quality.auto")
        case .lowest: return String(localized: "iptv.quality.lowest")
        case .sd: return String(localized: "iptv.quality.sd")
        case .hd: return String(localized: "iptv.quality.hd")
        case .fullHD: return String(localized: "iptv.quality.fhd")
        case .uhd: return String(localized: "iptv.quality.uhd")
        case .highest: return String(localized: "iptv.quality.highest")
        }
    }
}

struct IPTVSource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var streamURLString: String
    var name: String?
    var quality: IPTVStreamQuality
    var headers: [String: String]
    var successCount: Int
    var failureCount: Int
    var lastSuccess: Date?
    var lastFailure: Date?
    var lastProbeAt: Date?
    var lastProbeLatencyMs: Int?
    var lastProbeMbps: Double?
    /// Skip in selection until this time after failed/slow probe.
    var disabledUntil: Date?

    var isTemporarilyDisabled: Bool {
        guard let until = disabledUntil else { return false }
        return until > Date()
    }

    /// Human-readable probe result for source lists, e.g. "128 ms · 3.2 Mbps" / "失败".
    var probeResultLabel: String? {
        if isTemporarilyDisabled {
            return String(localized: "iptv.probe_failed")
        }
        guard lastProbeAt != nil else { return nil }
        var parts: [String] = []
        if let ms = lastProbeLatencyMs {
            if ms >= 1000 {
                parts.append(String(format: "%.1f s", Double(ms) / 1000.0))
            } else {
                parts.append("\(ms) ms")
            }
        }
        if let mbps = lastProbeMbps, mbps > 0 {
            if mbps >= 10 {
                parts.append(String(format: "%.0f Mbps", mbps))
            } else {
                parts.append(String(format: "%.1f Mbps", mbps))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var streamURL: URL? { IPTVNetwork.normalizeURL(from: streamURLString) }

    var protocolType: IPTVStreamProtocol {
        guard let url = streamURL else { return .unknown }
        let s = url.absoluteString.lowercased()
        if s.contains(".m3u8") { return .hls }
        if s.contains(".ts") { return .mpegts }
        if url.scheme == "https" { return .https }
        if url.scheme == "http" { return .http }
        return .unknown
    }

    init(
        id: UUID = UUID(),
        streamURLString: String,
        name: String? = nil,
        quality: IPTVStreamQuality = .unknown,
        headers: [String: String] = [:],
        successCount: Int = 0,
        failureCount: Int = 0,
        lastSuccess: Date? = nil,
        lastFailure: Date? = nil,
        lastProbeAt: Date? = nil,
        lastProbeLatencyMs: Int? = nil,
        lastProbeMbps: Double? = nil,
        disabledUntil: Date? = nil
    ) {
        self.id = id
        self.streamURLString = streamURLString
        self.name = name
        self.quality = quality
        self.headers = headers
        self.successCount = successCount
        self.failureCount = failureCount
        self.lastSuccess = lastSuccess
        self.lastFailure = lastFailure
        self.lastProbeAt = lastProbeAt
        self.lastProbeLatencyMs = lastProbeLatencyMs
        self.lastProbeMbps = lastProbeMbps
        self.disabledUntil = disabledUntil
    }

    enum CodingKeys: String, CodingKey {
        case id, streamURLString, name, quality, headers
        case successCount, failureCount, lastSuccess, lastFailure
        case lastProbeAt, lastProbeLatencyMs, lastProbeMbps, disabledUntil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        streamURLString = try c.decode(String.self, forKey: .streamURLString)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        quality = try c.decodeIfPresent(IPTVStreamQuality.self, forKey: .quality) ?? .unknown
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        successCount = try c.decodeIfPresent(Int.self, forKey: .successCount) ?? 0
        failureCount = try c.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
        lastSuccess = try c.decodeIfPresent(Date.self, forKey: .lastSuccess)
        lastFailure = try c.decodeIfPresent(Date.self, forKey: .lastFailure)
        lastProbeAt = try c.decodeIfPresent(Date.self, forKey: .lastProbeAt)
        lastProbeLatencyMs = try c.decodeIfPresent(Int.self, forKey: .lastProbeLatencyMs)
        lastProbeMbps = try c.decodeIfPresent(Double.self, forKey: .lastProbeMbps)
        disabledUntil = try c.decodeIfPresent(Date.self, forKey: .disabledUntil)
    }
}

// MARK: - Channel

struct IPTVChannel: Identifiable, Codable, Hashable, Sendable {
    let id: String // stable identity
    var name: String
    var logoURLString: String?
    var group: String?
    var tvgID: String?
    var language: String?
    var country: String?
    var sources: [IPTVSource]
    var playlistId: UUID

    var logoURL: URL? { logoURLString.flatMap { IPTVNetwork.normalizeURL(from: $0) } }

    init(
        id: String,
        name: String,
        logoURLString: String? = nil,
        group: String? = nil,
        tvgID: String? = nil,
        language: String? = nil,
        country: String? = nil,
        sources: [IPTVSource] = [],
        playlistId: UUID
    ) {
        self.id = id
        self.name = name
        self.logoURLString = logoURLString
        self.group = group
        self.tvgID = tvgID
        self.language = language
        self.country = country
        self.sources = sources
        self.playlistId = playlistId
    }
}

// MARK: - Preferences

struct IPTVPreferences: Codable, Sendable {
    var defaultQuality: IPTVStreamQuality
    var autoSwitchSource: Bool
    var favoriteChannelIds: [String]
    /// Prefer lower quality when measured throughput is below need.
    var adaptiveQuality: Bool
    /// Show IPTV diagnostic HUD during playback.
    var showDiagnosticsHUD: Bool
    /// Optional global EPG URL (overrides / supplements playlist header).
    var globalEPGURLString: String?
    /// Probe sources for latency/speed before use; slow/failed sources are ignored until cooldown ends.
    var autoProbeSources: Bool
    /// Minimum hours between probes of a healthy source (default 6).
    var probeIntervalHours: Double
    /// Minutes to ignore a failed/slow source before re-probe (default 90).
    var probeFailureCooldownMinutes: Double
    /// Mark source bad if TTFB exceeds this many ms (default 8000).
    var probeMaxLatencyMs: Int
    /// Same tvg-name in different groups counts as one channel when true.
    var mergeAcrossGroups: Bool

    var globalEPGURL: URL? { globalEPGURLString.flatMap { IPTVNetwork.normalizeURL(from: $0) } }

    static let `default` = IPTVPreferences(
        defaultQuality: .unknown, // auto
        autoSwitchSource: true,
        favoriteChannelIds: [],
        adaptiveQuality: true,
        showDiagnosticsHUD: false,
        globalEPGURLString: nil,
        autoProbeSources: true,
        probeIntervalHours: 6,
        probeFailureCooldownMinutes: 90,
        probeMaxLatencyMs: 8000,
        mergeAcrossGroups: false
    )

    enum CodingKeys: String, CodingKey {
        case defaultQuality, autoSwitchSource, favoriteChannelIds
        case adaptiveQuality, showDiagnosticsHUD, globalEPGURLString
        case autoProbeSources, probeIntervalHours, probeFailureCooldownMinutes, probeMaxLatencyMs, mergeAcrossGroups
    }

    init(
        defaultQuality: IPTVStreamQuality,
        autoSwitchSource: Bool,
        favoriteChannelIds: [String],
        adaptiveQuality: Bool,
        showDiagnosticsHUD: Bool,
        globalEPGURLString: String?,
        autoProbeSources: Bool = true,
        probeIntervalHours: Double = 6,
        probeFailureCooldownMinutes: Double = 90,
        probeMaxLatencyMs: Int = 8000,
        mergeAcrossGroups: Bool = false
    ) {
        self.defaultQuality = defaultQuality
        self.autoSwitchSource = autoSwitchSource
        self.favoriteChannelIds = favoriteChannelIds
        self.adaptiveQuality = adaptiveQuality
        self.showDiagnosticsHUD = showDiagnosticsHUD
        self.globalEPGURLString = globalEPGURLString
        self.autoProbeSources = autoProbeSources
        self.probeIntervalHours = probeIntervalHours
        self.probeFailureCooldownMinutes = probeFailureCooldownMinutes
        self.probeMaxLatencyMs = probeMaxLatencyMs
        self.mergeAcrossGroups = mergeAcrossGroups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultQuality = try c.decodeIfPresent(IPTVStreamQuality.self, forKey: .defaultQuality) ?? .unknown
        autoSwitchSource = try c.decodeIfPresent(Bool.self, forKey: .autoSwitchSource) ?? true
        favoriteChannelIds = try c.decodeIfPresent([String].self, forKey: .favoriteChannelIds) ?? []
        adaptiveQuality = try c.decodeIfPresent(Bool.self, forKey: .adaptiveQuality) ?? true
        showDiagnosticsHUD = try c.decodeIfPresent(Bool.self, forKey: .showDiagnosticsHUD) ?? false
        globalEPGURLString = try c.decodeIfPresent(String.self, forKey: .globalEPGURLString)
        autoProbeSources = try c.decodeIfPresent(Bool.self, forKey: .autoProbeSources) ?? true
        probeIntervalHours = try c.decodeIfPresent(Double.self, forKey: .probeIntervalHours) ?? 6
        probeFailureCooldownMinutes = try c.decodeIfPresent(Double.self, forKey: .probeFailureCooldownMinutes) ?? 90
        probeMaxLatencyMs = try c.decodeIfPresent(Int.self, forKey: .probeMaxLatencyMs) ?? 8000
        mergeAcrossGroups = try c.decodeIfPresent(Bool.self, forKey: .mergeAcrossGroups) ?? false
    }
}
