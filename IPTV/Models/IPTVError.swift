import Foundation

enum IPTVError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidPlaylistEncoding
    case emptyPlaylist
    case playlistTooLarge
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "iptv.error.invalid_url")
        case .invalidPlaylistEncoding:
            return String(localized: "iptv.error.encoding")
        case .emptyPlaylist:
            return String(localized: "iptv.error.empty")
        case .playlistTooLarge:
            return String(localized: "iptv.error.too_large")
        case .downloadFailed(let message):
            return message
        }
    }
}
