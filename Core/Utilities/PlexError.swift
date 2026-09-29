import Foundation

/// Unified domain error surface. Map infrastructure failures into these
/// before they reach ViewModels / UI.
enum PlexError: Error, LocalizedError, Sendable {
    case authentication(AuthenticationError)
    case network(NetworkError)
    case serverUnavailable
    case invalidResponse
    case decoding(String)
    case playback(PlaybackError)
    case transcoding(TranscodingError)
    case mediaUnavailable
    case permission
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .authentication(let e):
            return e.localizedDescription
        case .network(let e):
            return e.localizedDescription
        case .serverUnavailable:
            return "Server is unavailable"
        case .invalidResponse:
            return "Invalid response from server"
        case .decoding(let detail):
            return "Failed to decode response: \(detail)"
        case .playback(let e):
            return e.localizedDescription
        case .transcoding(let e):
            return e.localizedDescription
        case .mediaUnavailable:
            return "This content is not available right now"
        case .permission:
            return "You do not have permission to access this content"
        case .cancelled:
            return "Operation cancelled"
        case .unknown(let message):
            return message
        }
    }
}

enum AuthenticationError: Error, LocalizedError, Sendable {
    case notSignedIn
    case pinExpired
    case pinDenied
    case tokenInvalid
    case tokenMissing
    case keychain(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .pinExpired: return "Sign-in code expired"
        case .pinDenied: return "Sign-in was denied"
        case .tokenInvalid: return "Session expired — please sign in again"
        case .tokenMissing: return "Missing authentication token"
        case .keychain(let e): return "Secure storage error: \(e.localizedDescription)"
        }
    }
}

enum NetworkError: Error, LocalizedError, Sendable {
    case offline
    case timeout
    case transport(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .offline: return "No network connection"
        case .timeout: return "Request timed out"
        case .transport(let msg): return msg
        case .httpStatus(let code): return "Server returned \(code)"
        }
    }
}

enum PlaybackError: Error, LocalizedError, Sendable {
    case assetLoadFailed(String)
    case unsupportedFormat(String)
    case sessionFailed
    case playerError(String)

    var errorDescription: String? {
        switch self {
        case .assetLoadFailed(let r): return "Could not load media: \(r)"
        case .unsupportedFormat(let r): return "Unsupported format: \(r)"
        case .sessionFailed: return "Playback session failed"
        case .playerError(let r): return r
        }
    }
}

enum TranscodingError: Error, LocalizedError, Sendable {
    case decisionFailed(String)
    case sessionStartFailed
    case sessionEndedUnexpectedly

    var errorDescription: String? {
        switch self {
        case .decisionFailed(let r): return "Transcode decision failed: \(r)"
        case .sessionStartFailed: return "Could not start transcode session"
        case .sessionEndedUnexpectedly: return "Transcode session ended unexpectedly"
        }
    }
}
