import Foundation

/// Line-oriented M3U parser that never keeps the full playlist string in one buffer
/// when fed incrementally. Suitable for multi-MB playlists.
enum M3UStreamingParser {
    static let maxBytes = 20 * 1024 * 1024
    static let maxEntries = 50_000

    static func parse(data: Data) throws -> M3UParseResult {
        if data.count > maxBytes { throw IPTVError.playlistTooLarge }
        // Delegate to robust state-machine parser (EXTINF↔URL pairing, opts, etc.)
        let result = try M3UParser.parse(data: data)
        if result.entries.count > maxEntries {
            return M3UParseResult(epgURL: result.epgURL, entries: Array(result.entries.prefix(maxEntries)))
        }
        return result
    }

    /// Download with size cap and parse.
    /// Uses `IPTVNetwork.session` so LAN `http://192.168.x.x` works without WAN Internet.
    static func downloadAndParse(url: URL, session: URLSession = IPTVNetwork.session) async throws -> M3UParseResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/vnd.apple.mpegurl, audio/mpegurl, application/x-mpegURL, text/plain, */*",
            forHTTPHeaderField: "Accept"
        )
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw IPTVError.downloadFailed("HTTP \(http.statusCode)")
            }

            var data = Data()
            data.reserveCapacity(min(2 * 1024 * 1024, maxBytes))
            for try await b in bytes {
                data.append(b)
                if data.count > maxBytes {
                    throw IPTVError.playlistTooLarge
                }
            }
            return try parse(data: data)
        } catch let error as IPTVError {
            throw error
        } catch {
            throw IPTVError.downloadFailed(IPTVNetwork.describe(error))
        }
    }

    static func parseLines(_ text: String) -> M3UParseResult {
        var epgURL: URL?
        var entries: [M3UEntry] = []
        entries.reserveCapacity(min(4096, maxEntries))
        var pendingInfo: (duration: TimeInterval?, name: String, attrs: [String: String])?
        var pendingHeaders: [String: String] = [:]

        text.enumerateLines { line, stop in
            if entries.count >= maxEntries {
                stop = true
                return
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if trimmed.hasPrefix("#EXTM3U") {
                let attrs = M3UParser.parseAttributesPublic(from: String(trimmed.dropFirst("#EXTM3U".count)))
                if let u = attrs["url-tvg"] ?? attrs["x-tvg-url"] ?? attrs["tvg-url"] {
                    epgURL = IPTVNetwork.normalizeURL(from: u)
                }
                return
            }
            if trimmed.hasPrefix("#EXTVLCOPT:") {
                let body = String(trimmed.dropFirst("#EXTVLCOPT:".count))
                let lower = body.lowercased()
                if lower.hasPrefix("http-user-agent="),
                   let v = body.split(separator: "=", maxSplits: 1).last {
                    pendingHeaders["User-Agent"] = String(v)
                } else if lower.hasPrefix("http-referrer=") || lower.hasPrefix("http-referer="),
                          let v = body.split(separator: "=", maxSplits: 1).last {
                    pendingHeaders["Referer"] = String(v)
                } else if lower.hasPrefix("http-origin="),
                          let v = body.split(separator: "=", maxSplits: 1).last {
                    pendingHeaders["Origin"] = String(v)
                }
                return
            }
            if trimmed.hasPrefix("#EXTINF:") {
                let body = String(trimmed.dropFirst("#EXTINF:".count))
                let (duration, rest) = M3UParser.splitDurationPublic(body)
                let (attrs, name) = M3UParser.splitAttrsAndNamePublic(rest)
                pendingInfo = (duration, name, attrs)
                return
            }
            if trimmed.hasPrefix("#") { return }

            guard let url = IPTVNetwork.normalizeURL(from: trimmed) else { return }
            let info = pendingInfo
            let attrs = info?.attrs ?? [:]
            let name = (info?.name.isEmpty == false ? info!.name : (attrs["tvg-name"] ?? "Channel"))
            entries.append(
                M3UEntry(
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
                    headers: pendingHeaders,
                    opts: []
                )
            )
            pendingInfo = nil
            pendingHeaders = [:]
        }

        return M3UParseResult(epgURL: epgURL, entries: entries)
    }
}
