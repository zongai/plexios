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
        config.httpAdditionalHeaders = [
            "User-Agent": "PlexiOS/1.0 (IPTV; iOS)"
        ]
        return URLSession(configuration: config)
    }()

    /// Normalize playlist / stream URLs.
    /// Supports http/https, IPv4, bracketed & bare IPv6, scheme-less hosts.
    static func normalizeURL(from raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if s.contains(" ") {
            s = s.replacingOccurrences(of: " ", with: "%20")
        }

        if !s.contains("://") {
            s = "http://" + s
        }

        if let fixed = bracketUnbracketedIPv6(in: s) {
            s = fixed
        }

        if let url = URL(string: s), url.scheme != nil, url.host != nil || isOpaqueStreamScheme(url.scheme) {
            return url
        }

        guard var components = URLComponents(string: s) else { return nil }
        if components.scheme == nil { components.scheme = "http" }
        if components.host == nil, let repaired = repairIPv6Components(s) {
            return repaired
        }
        guard components.scheme != nil else { return nil }
        return components.url
    }

    private static func isOpaqueStreamScheme(_ scheme: String?) -> Bool {
        guard let scheme else { return false }
        return ["udp", "rtp", "rtsp", "mms", "mmsh"].contains(scheme.lowercased())
    }

    /// Insert brackets around IPv6 literals when missing.
    private static func bracketUnbracketedIPv6(in urlString: String) -> String? {
        guard let schemeRange = urlString.range(of: "://") else { return nil }
        let afterScheme = urlString[schemeRange.upperBound...]
        if afterScheme.hasPrefix("[") { return nil }

        let authorityEnd = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
        let authority = authorityEnd.map { String(afterScheme[..<$0]) } ?? String(afterScheme)
        let remainder = authorityEnd.map { String(afterScheme[$0...]) } ?? ""

        var userinfo = ""
        var hostPort = authority
        if let at = authority.lastIndex(of: "@") {
            userinfo = String(authority[...at])
            hostPort = String(authority[authority.index(after: at)...])
        }

        let colonCount = hostPort.filter { $0 == ":" }.count
        guard colonCount >= 2 else { return nil }

        var host = hostPort
        var portSuffix = ""
        if let lastColon = hostPort.lastIndex(of: ":") {
            let after = String(hostPort[hostPort.index(after: lastColon)...])
            if !after.isEmpty, after.allSatisfy(\.isNumber), after.count <= 5 {
                let before = String(hostPort[..<lastColon])
                let beforeColons = before.filter { $0 == ":" }.count
                if beforeColons >= 2 {
                    host = before
                    portSuffix = ":" + after
                }
            }
        }

        let ipv6Charset = CharacterSet(charactersIn: "0123456789abcdefABCDEF:")
        guard host.unicodeScalars.allSatisfy({ ipv6Charset.contains($0) }) else { return nil }

        let scheme = String(urlString[..<schemeRange.upperBound])
        return scheme + userinfo + "[" + host + "]" + portSuffix + remainder
    }

    private static func repairIPv6Components(_ s: String) -> URL? {
        guard let fixed = bracketUnbracketedIPv6(in: s) else { return nil }
        return URL(string: fixed)
    }

    static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return true }
        if h.hasPrefix("10.") { return true }
        if h.hasPrefix("192.168.") { return true }
        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        if h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe80") { return true }
        return false
    }

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
