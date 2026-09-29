import Foundation

/// Shared networking for IPTV M3U / EPG / probe — works on LAN even without WAN “Internet”.
enum IPTVNetwork {
    /// Ephemeral session that does not wait for Internet reachability.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Prefer IPv4 for typical home IPTV boxes when dual-stack misbehaves.
        config.httpAdditionalHeaders = [
            "User-Agent": "PlexiOS/1.0 (IPTV; iOS)"
        ]
        return URLSession(configuration: config)
    }()

    /// Normalize user-entered playlist / stream URLs (`http://192.168.x.x/...`).
    static func normalizeURL(from raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Allow scheme-less LAN paths: 192.168.1.10/iptv.m3u
        if !s.contains("://") {
            s = "http://" + s
        }
        guard var components = URLComponents(string: s) else { return nil }
        if components.scheme == nil {
            components.scheme = "http"
        }
        // Reject clearly broken hosts
        guard let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }

    static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return true }
        if h.hasPrefix("10.") { return true }
        if h.hasPrefix("192.168.") { return true }
        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    /// Map URL / ATS errors into actionable IPTV messages (incl. Chinese system -1009).
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDataNotAllowed:
                return String(localized: "iptv.error.no_route")
            case NSURLErrorTimedOut:
                return String(localized: "iptv.error.timeout")
            case NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed:
                return String(localized: "iptv.error.host")
            case NSURLErrorCannotConnectToHost:
                return String(localized: "iptv.error.connect")
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return String(localized: "iptv.error.ats")
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateUntrusted:
                return String(localized: "iptv.error.tls")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
