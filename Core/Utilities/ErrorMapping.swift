import Foundation

/// Maps infrastructure errors into the domain `PlexError` surface.
enum ErrorMapping {
    static func map(_ error: Error) -> PlexError {
        if let plex = error as? PlexError {
            return plex
        }
        if error is CancellationError {
            return .cancelled
        }
        if let http = error as? HTTPClient.HTTPClientError {
            return mapHTTP(http)
        }
        if let urlError = error as? URLError {
            return mapURLError(urlError)
        }
        return .unknown(error.localizedDescription)
    }

    static func mapHTTP(_ error: HTTPClient.HTTPClientError) -> PlexError {
        switch error {
        case .invalidURL, .nonHTTPResponse:
            return .invalidResponse
        case .httpStatus(let code, _):
            switch code {
            case 401, 403:
                return .authentication(.tokenInvalid)
            case 404:
                // Used for missing metadata items; hub/section 404s also land here.
                // Prefer a neutral message — UI can still say "not available".
                return .mediaUnavailable
            case 408, 504:
                return .network(.timeout)
            case 502, 503:
                return .serverUnavailable
            default:
                return .network(.httpStatus(code))
            }
        case .transport(let underlying):
            if let urlError = underlying as? URLError {
                return mapURLError(urlError)
            }
            return .network(.transport(underlying.localizedDescription))
        }
    }

    static func mapURLError(_ error: URLError) -> PlexError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .network(.offline)
        case .timedOut:
            return .network(.timeout)
        case .cancelled:
            return .cancelled
        default:
            return .network(.transport(error.localizedDescription))
        }
    }

    /// User-facing recovery suggestion when available.
    static func recoverySuggestion(for error: PlexError) -> String? {
        switch error {
        case .network(.offline):
            return "Check your Wi‑Fi or cellular connection and try again."
        case .network(.timeout):
            return "The server took too long to respond. Try again on a stronger network."
        case .serverUnavailable:
            return "Make sure your Plex Media Server is running and reachable."
        case .authentication(.tokenInvalid), .authentication(.notSignedIn):
            return "Sign in again to refresh your session."
        case .authentication(.pinExpired):
            return "Request a new code and authorize it at plex.tv/link."
        default:
            return nil
        }
    }
}
