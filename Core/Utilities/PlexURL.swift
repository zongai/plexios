import Foundation

/// Safe URL joining for Plex paths.
///
/// **Never** pass multi-segment paths to `URL.appendingPathComponent(_:)` —
/// Foundation percent-encodes `/` as `%2F`, so `"hubs/home"` becomes
/// `hubs%2Fhome` and PMS returns **404** (surfaced as `mediaUnavailable`).
enum PlexURL {
    /// Joins `base` with a Plex-style path that may contain `/` and `:` segments
    /// (e.g. `"hubs/home"`, `"library/metadata/123"`, `":/timeline"`,
    /// `"video/:/transcode/universal/start.m3u8"`).
    static func join(_ base: URL, path: String) -> URL? {
        let trimmedBase = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !trimmedPath.isEmpty else { return base }
        return URL(string: trimmedBase + "/" + trimmedPath)
    }

    /// Convenience: join + optional query items.
    static func join(_ base: URL, path: String, query: [URLQueryItem]) -> URL? {
        guard let url = join(base, path: path) else { return nil }
        guard !query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = query
        return components?.url
    }
}
