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

    var url: URL? { URL(string: urlString) }
    var epgURL: URL? { epgURLString.flatMap(URL.init(string:)) }

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
        case .unknown: return "Auto / Unknown"
        case .lowest: return "Lowest"
        case .sd: return "480p"
        case .hd: return "720p"
        case .fullHD: return "1080p"
        case .uhd: return "4K"
        case .highest: return "Highest"
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

    var streamURL: URL? { URL(string: streamURLString) }

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
        lastFailure: Date? = nil
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

    var logoURL: URL? { logoURLString.flatMap(URL.init(string:)) }

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

    var globalEPGURL: URL? { globalEPGURLString.flatMap(URL.init(string:)) }

    static let `default` = IPTVPreferences(
        defaultQuality: .unknown, // auto
        autoSwitchSource: true,
        favoriteChannelIds: [],
        adaptiveQuality: true,
        showDiagnosticsHUD: false,
        globalEPGURLString: nil
    )

    enum CodingKeys: String, CodingKey {
        case defaultQuality, autoSwitchSource, favoriteChannelIds
        case adaptiveQuality, showDiagnosticsHUD, globalEPGURLString
    }

    init(
        defaultQuality: IPTVStreamQuality,
        autoSwitchSource: Bool,
        favoriteChannelIds: [String],
        adaptiveQuality: Bool,
        showDiagnosticsHUD: Bool,
        globalEPGURLString: String?
    ) {
        self.defaultQuality = defaultQuality
        self.autoSwitchSource = autoSwitchSource
        self.favoriteChannelIds = favoriteChannelIds
        self.adaptiveQuality = adaptiveQuality
        self.showDiagnosticsHUD = showDiagnosticsHUD
        self.globalEPGURLString = globalEPGURLString
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultQuality = try c.decodeIfPresent(IPTVStreamQuality.self, forKey: .defaultQuality) ?? .unknown
        autoSwitchSource = try c.decodeIfPresent(Bool.self, forKey: .autoSwitchSource) ?? true
        favoriteChannelIds = try c.decodeIfPresent([String].self, forKey: .favoriteChannelIds) ?? []
        adaptiveQuality = try c.decodeIfPresent(Bool.self, forKey: .adaptiveQuality) ?? true
        showDiagnosticsHUD = try c.decodeIfPresent(Bool.self, forKey: .showDiagnosticsHUD) ?? false
        globalEPGURLString = try c.decodeIfPresent(String.self, forKey: .globalEPGURLString)
    }
}
