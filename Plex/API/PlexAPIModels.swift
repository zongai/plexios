import Foundation

// MARK: - API DTOs (Decodable only — map to domain models)

struct APIMediaContainer<T: Decodable>: Decodable {
    let mediaContainer: T

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

// plex.tv PIN

struct APIPINResponse: Decodable {
    let id: Int
    let code: String
    let expiresIn: Int?
    let authToken: String?
    let product: String?
}

// plex.tv resources

struct APIResource: Decodable {
    let name: String?
    let product: String?
    let productVersion: String?
    let platform: String?
    let clientIdentifier: String?
    let provides: String?
    let accessToken: String?
    let owned: Bool?
    let home: Bool?
    let publicAddress: String?
    let connections: [APIConnection]?

    var isServer: Bool {
        (provides ?? "").split(separator: ",").map(String.init).contains("server")
    }

    var machineIdentifier: String {
        clientIdentifier ?? ""
    }
}

struct APIConnection: Decodable {
    let protocolName: String?
    let address: String?
    let port: Int?
    let uri: String?
    let local: Bool?
    let relay: Bool?
    let ipv6: Bool?

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case address, port, uri, local, relay
        case ipv6 = "IPv6"
    }
}

// PMS library sections

struct APILibrarySectionsContainer: Decodable {
    let size: Int?
    let directory: [APIDirectory]?

    enum CodingKeys: String, CodingKey {
        case size
        case directory = "Directory"
    }
}

struct APIDirectory: Decodable {
    let key: String?
    let uuid: String?
    let type: String?
    let title: String?
    let agent: String?
    let scanner: String?
    let thumb: String?
    let art: String?
    let count: Int?
    let updatedAt: Int?
}

// Hubs

struct APIHubsContainer: Decodable {
    let size: Int?
    let hub: [APIHub]?

    enum CodingKeys: String, CodingKey {
        case size
        case Hub
        case hub
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        hub = try c.decodeIfPresent([APIHub].self, forKey: .Hub)
            ?? c.decodeIfPresent([APIHub].self, forKey: .hub)
    }
}

struct APIHub: Decodable {
    let key: String?
    let hubKey: String?
    let hubIdentifier: String?
    let title: String?
    let type: String?
    let style: String?
    let size: Int?
    let more: Bool?
    let metadata: [APIMetadata]?

    enum CodingKeys: String, CodingKey {
        case key, hubKey, hubIdentifier, title, type, style, size, more
        case metadata = "Metadata"
    }
}

// Metadata

struct APIMetadataContainer: Decodable {
    let size: Int?
    let allowSync: Bool?
    let metadata: [APIMetadata]?

    enum CodingKeys: String, CodingKey {
        case size, allowSync
        case Metadata
        case metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        allowSync = try c.decodeIfPresent(Bool.self, forKey: .allowSync)
        metadata = try c.decodeIfPresent([APIMetadata].self, forKey: .Metadata)
            ?? c.decodeIfPresent([APIMetadata].self, forKey: .metadata)
    }
}

struct APIMetadata: Decodable {
    let ratingKey: String?
    let key: String?
    let type: String?
    let title: String?
    let summary: String?
    let year: Int?
    let contentRating: String?
    let rating: Double?
    let audienceRating: Double?
    let userRating: Double?
    let duration: Int64?
    let viewOffset: Int64?
    let viewCount: Int?
    let lastViewedAt: Int?
    let originallyAvailableAt: String?
    let thumb: String?
    let art: String?
    let parentThumb: String?
    let grandparentThumb: String?
    let parentTitle: String?
    let grandparentTitle: String?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let index: Int?
    let parentIndex: Int?
    let leafCount: Int?
    let viewedLeafCount: Int?
    let childCount: Int?
    let studio: String?
    let tagline: String?
    let genre: [APITag]?
    let director: [APITag]?
    let writer: [APITag]?
    let role: [APIRole]?
    let media: [APIMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, title, summary, year, contentRating
        case rating, audienceRating, userRating, duration, viewOffset, viewCount
        case lastViewedAt, originallyAvailableAt, thumb, art
        case parentThumb, grandparentThumb, parentTitle, grandparentTitle
        case parentRatingKey, grandparentRatingKey, index, parentIndex
        case leafCount, viewedLeafCount, childCount, studio, tagline
        case genre = "Genre"
        case director = "Director"
        case writer = "Writer"
        case role = "Role"
        case media = "Media"
    }
}

struct APITag: Decodable {
    let tag: String?
}

struct APIRole: Decodable {
    let tag: String?
    let role: String?
    let thumb: String?
}

struct APIMedia: Decodable {
    let id: Int?
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
    let part: [APIPart]?

    enum CodingKeys: String, CodingKey {
        case id, duration, bitrate, width, height
        case videoCodec, audioCodec, container, videoResolution
        case videoFrameRate, videoProfile, audioChannels
        case part = "Part"
    }
}

struct APIPart: Decodable {
    let id: Int?
    let key: String?
    let duration: Int64?
    let size: Int64?
    let container: String?
    let file: String?
    let accessible: Bool?
    let stream: [APIStream]?

    enum CodingKeys: String, CodingKey {
        case id, key, duration, size, container, file, accessible
        case stream = "Stream"
    }
}

struct APIStream: Decodable {
    let id: Int?
    let streamType: Int?
    let codec: String?
    let format: String?
    let language: String?
    let languageCode: String?
    let displayTitle: String?
    let extendedDisplayTitle: String?
    let title: String?
    let forced: Bool?
    let selected: Bool?
    let isDefault: Bool?
    let external: Bool?
    let bitrate: Int?
    let channels: Int?
    let key: String?
    let bitDepth: Int?

    enum CodingKeys: String, CodingKey {
        case id, streamType, codec, format, language, languageCode
        case displayTitle, extendedDisplayTitle, title
        case forced, selected, external, bitrate, channels, key, bitDepth
        case isDefault = "default"
    }
}

// Identity probe

struct APIIdentityContainer: Decodable {
    let mediaContainer: APIIdentity?

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct APIIdentity: Decodable {
    let machineIdentifier: String?
    let version: String?
    let claimed: Bool?
}
