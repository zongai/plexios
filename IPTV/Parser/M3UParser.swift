import Foundation

struct M3UEntry: Sendable {
    var duration: TimeInterval?
    var name: String
    var tvgID: String?
    var tvgName: String?
    var tvgLogo: String?
    var groupTitle: String?
    var country: String?
    var language: String?
    var attributes: [String: String]
    var streamURL: URL
    var headers: [String: String]
}

struct M3UParseResult: Sendable {
    var epgURL: URL?
    var entries: [M3UEntry]
}

enum M3UParser {
    /// Tolerant EXTM3U parser. Unknown attributes are kept; bad lines are skipped.
    static func parse(data: Data) throws -> M3UParseResult {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw IPTVError.invalidPlaylistEncoding
        }
        return parse(text: text)
    }

    static func parse(text: String) -> M3UParseResult {
        var epgURL: URL?
        var entries: [M3UEntry] = []
        var pendingInfo: (duration: TimeInterval?, name: String, attrs: [String: String])?
        var pendingHeaders: [String: String] = [:]

        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in lines {
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTM3U") {
                let attrs = parseAttributes(from: String(line.dropFirst("#EXTM3U".count)))
                if let u = attrs["url-tvg"] ?? attrs["x-tvg-url"] ?? attrs["tvg-url"] {
                    epgURL = URL(string: u)
                }
                continue
            }

            if line.hasPrefix("#EXTVLCOPT:") {
                let body = String(line.dropFirst("#EXTVLCOPT:".count))
                if body.lowercased().hasPrefix("http-user-agent="),
                   let v = body.split(separator: "=", maxSplits: 1).last {
                    pendingHeaders["User-Agent"] = String(v)
                } else if body.lowercased().hasPrefix("http-referrer=")
                            || body.lowercased().hasPrefix("http-referer="),
                          let v = body.split(separator: "=", maxSplits: 1).last {
                    pendingHeaders["Referer"] = String(v)
                } else if body.lowercased().hasPrefix("http-origin="),
                          let v = body.split(separator: "=", maxSplits: 1).last {
                    pendingHeaders["Origin"] = String(v)
                }
                continue
            }

            if line.hasPrefix("#EXTINF:") {
                let body = String(line.dropFirst("#EXTINF:".count))
                let (duration, rest) = splitDuration(body)
                let (attrs, name) = splitAttrsAndName(rest)
                pendingInfo = (duration, name, attrs)
                continue
            }

            if line.hasPrefix("#") { continue }

            // Stream URL line
            guard let url = URL(string: line), url.scheme != nil else { continue }
            let info = pendingInfo
            let attrs = info?.attrs ?? [:]
            let name = (info?.name.isEmpty == false ? info!.name : (attrs["tvg-name"] ?? "Channel"))
            let entry = M3UEntry(
                duration: info?.duration,
                name: name,
                tvgID: attrs["tvg-id"],
                tvgName: attrs["tvg-name"],
                tvgLogo: attrs["tvg-logo"],
                groupTitle: attrs["group-title"],
                country: attrs["tvg-country"],
                language: attrs["tvg-language"],
                attributes: attrs,
                streamURL: url,
                headers: pendingHeaders
            )
            entries.append(entry)
            pendingInfo = nil
            pendingHeaders = [:]
        }

        return M3UParseResult(epgURL: epgURL, entries: entries)
    }

    // MARK: - Helpers (shared with streaming parser)

    static func splitDurationPublic(_ body: String) -> (TimeInterval?, String) {
        splitDuration(body)
    }

    static func splitAttrsAndNamePublic(_ rest: String) -> ([String: String], String) {
        splitAttrsAndName(rest)
    }

    static func parseAttributesPublic(from text: String) -> [String: String] {
        parseAttributes(from: text)
    }

    private static func splitDuration(_ body: String) -> (TimeInterval?, String) {
        // "-1 tvg-id=...,Name" or "10.5,Name"
        guard let comma = body.firstIndex(of: ",") else {
            if let d = TimeInterval(body.trimmingCharacters(in: .whitespaces)) {
                return (d < 0 ? -1 : d, "")
            }
            return (nil, body)
        }
        let head = body[..<comma].trimmingCharacters(in: .whitespaces)
        let tail = String(body[body.index(after: comma)...])
        // head may be "-1 tvg-id=..."
        let parts = head.split(separator: " ", maxSplits: 1).map(String.init)
        var duration: TimeInterval?
        var attrPart = head
        if let first = parts.first, let d = TimeInterval(first) {
            duration = d
            attrPart = parts.count > 1 ? parts[1] : ""
        }
        let rest = attrPart.isEmpty ? tail : (attrPart + "," + tail)
        // Actually if duration consumed, rest attrs are in parts[1] + comma name
        if parts.count > 1 {
            return (duration, parts[1] + "," + tail)
        }
        return (duration, tail)
    }

    private static func splitAttrsAndName(_ rest: String) -> ([String: String], String) {
        // "tvg-id=\"x\" group-title=\"G\",Display Name"
        guard let lastComma = rest.lastIndex(of: ",") else {
            return (parseAttributes(from: rest), rest.trimmingCharacters(in: .whitespaces))
        }
        // Prefer last comma as name separator (attrs may contain commas rarely)
        let attrRegion = String(rest[..<lastComma])
        let name = String(rest[rest.index(after: lastComma)...]).trimmingCharacters(in: .whitespaces)
        return (parseAttributes(from: attrRegion), name)
    }

    private static func parseAttributes(from text: String) -> [String: String] {
        var result: [String: String] = [:]
        // key="value" or key=value
        let pattern = #"([A-Za-z0-9_-]+)=(\"[^\"]*\"|[^\s,]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let kr = Range(match.range(at: 1), in: text),
                  let vr = Range(match.range(at: 2), in: text) else { continue }
            var value = String(text[vr])
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result[String(text[kr]).lowercased()] = value
        }
        return result
    }
}

enum IPTVError: LocalizedError {
    case invalidURL
    case invalidPlaylistEncoding
    case playlistTooLarge
    case downloadFailed(String)
    case emptyPlaylist
    case noSources

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid playlist URL"
        case .invalidPlaylistEncoding: return "Could not decode playlist text"
        case .playlistTooLarge: return "Playlist is too large"
        case .downloadFailed(let m): return m
        case .emptyPlaylist: return "Playlist contains no channels"
        case .noSources: return "No playable sources"
        }
    }
}
