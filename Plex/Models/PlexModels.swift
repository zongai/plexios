import Foundation

// MARK: - Account / Auth

struct PlexUser: Identifiable, Hashable, Sendable {
    let id: String
    let uuid: String?
    let username: String?
    let email: String?
    let friendlyName: String?
    let thumb: URL?
    let home: Bool
    let restricted: Bool
}

struct PlexPin: Sendable {
    let id: Int
    let code: String
    let expiresIn: Int?
    let authToken: String?
}

// MARK: - Server & Connection

struct PlexServer: Identifiable, Hashable, Sendable {
    /// machineIdentifier is the stable identity
    var id: String { machineIdentifier }
    let machineIdentifier: String
    let name: String
    let product: String?
    let productVersion: String?
    let platform: String?
    let owned: Bool
    let home: Bool
    let accessToken: String
    var connections: [PlexConnection]
    var preferredConnection: PlexConnection?
}

struct PlexConnection: Identifiable, Hashable, Sendable {
    var id: String { uri }
    let uri: String
    let address: String?
    let port: Int?
    let protocolName: String // "http" | "https"
    let local: Bool
    let relay: Bool
    let ipv6: Bool
    var latencyMs: Double?
    var lastSuccess: Date?

    var baseURL: URL? { URL(string: uri) }

    /// Ranking score: lower is better.
    /// Local plain HTTP is preferred over local HTTPS-to-IP (self-signed / ATS issues).
    var rankScore: Int {
        var score = 0
        if relay { score += 1000 }
        if !local { score += 100 }
        // Prefer local http over local https-to-IP; still prefer remote https over remote http
        if local {
            if protocolName == "https" { score += 5 }
        } else if protocolName != "https" {
            score += 10
        }
        if ipv6 { score += 1 }
        return score
    }
}

// MARK: - Library

enum PlexLibraryType: String, Sendable, Hashable, Codable {
    case movie
    case show
    case artist
    case photo
    case mixed
    case unknown

    init(plexType: String?) {
        switch plexType?.lowercased() {
        case "movie": self = .movie
        case "show": self = .show
        case "artist": self = .artist
        case "photo": self = .photo
        case "mixed": self = .mixed
        default: self = .unknown
        }
    }

    init(typeNumber: Int?) {
        switch typeNumber {
        case 1: self = .movie
        case 2: self = .show
        case 8: self = .artist
        case 13: self = .photo
        default: self = .unknown
        }
    }
}

struct PlexLibrary: Identifiable, Hashable, Sendable, Codable {
    var id: String { key }
    let key: String
    let uuid: String?
    let title: String
    let type: PlexLibraryType
    let agent: String?
    let scanner: String?
    let thumb: String?
    let art: String?
    let count: Int?
    let updatedAt: Date?
}

// MARK: - Hub

struct PlexHub: Identifiable, Hashable, Sendable, Codable {
    var id: String { hubIdentifier ?? key }
    let key: String
    let hubIdentifier: String?
    let title: String
    let type: String?
    let style: String?
    let size: Int?
    let more: Bool
    var items: [PlexMetadata]
}

// MARK: - Metadata

enum PlexMetadataType: String, Sendable, Hashable, Codable {
    case movie, show, season, episode, artist, album, track
    case collection, playlist, person, clip, photo, trailer
    case unknown

    init(raw: String?) {
        guard let raw else { self = .unknown; return }
        self = PlexMetadataType(rawValue: raw.lowercased()) ?? .unknown
    }
}

struct PlexMetadata: Identifiable, Hashable, Sendable, Codable {
    var id: String { ratingKey }
    let ratingKey: String
    let key: String
    let type: PlexMetadataType
    let title: String
    let summary: String?
    let year: Int?
    let contentRating: String?
    let rating: Double?
    let audienceRating: Double?
    /// User rating 0–10; ≥1 typically means favorited / thumbed up on PMS.
    let userRating: Double?
    let duration: Int64?          // ms
    let viewOffset: Int64?        // ms
    let viewCount: Int?
    let lastViewedAt: Date?
    let originallyAvailableAt: String?
    let thumb: String?
    let art: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let parentTitle: String?
    let grandparentTitle: String?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let index: Int?               // episode / season number
    let parentIndex: Int?
    let librarySectionID: String?
    let librarySectionTitle: String?
    let leafCount: Int?
    let viewedLeafCount: Int?
    let childCount: Int?
    let studio: String?
    let tagline: String?
    let genres: [String]
    let directors: [String]
    let writers: [String]
    let actors: [PlexRole]
    let media: [PlexMedia]

    var isInProgress: Bool {
        guard let offset = viewOffset, offset > 0,
              let duration, duration > 0 else { return false }
        return Double(offset) / Double(duration) < 0.95
    }

    var isWatched: Bool {
        (viewCount ?? 0) > 0 && !isInProgress
    }

    var progressFraction: Double {
        guard let offset = viewOffset, let duration, duration > 0 else { return 0 }
        return min(1, Double(offset) / Double(duration))
    }

    var isFavorite: Bool {
        (userRating ?? 0) >= 1
    }
}

struct PlexRole: Hashable, Sendable, Codable {
    let tag: String
    let role: String?
    let thumb: String?
}

// MARK: - Media hierarchy

struct PlexMedia: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    let duration: Int64?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let videoCodec: String?
    let audioCodec: String?
    let container: String?
    let videoResolution: String?
    let videoFrameRate: String?
    let videoProfile: String?
    let audioChannels: Int?
    let parts: [PlexPart]
}

struct PlexPart: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    let key: String
    let duration: Int64?
    let size: Int64?
    let container: String?
    let file: String?
    let accessible: Bool?
    let streams: [PlexStream]
}

struct PlexStream: Identifiable, Hashable, Sendable, Codable {
    enum StreamType: Int, Sendable, Codable {
        case video = 1
        case audio = 2
        case subtitle = 3
        case unknown = 0
    }

    let id: Int
    let streamType: StreamType
    let codec: String?
    let format: String?
    let language: String?
    let languageCode: String?
    let displayTitle: String?
    let extendedDisplayTitle: String?
    let title: String?
    let isDefault: Bool
    let isForced: Bool
    let isSelected: Bool
    let isExternal: Bool
    let bitrate: Int?
    let channels: Int?
    let key: String?           // external subtitle path
    let bitDepth: Int?
}
