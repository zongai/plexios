import Foundation

enum ChannelNormalizer {
    /// Build channels: entries with the same exact `tvg-name` become one channel with multiple sources.
    static func channels(from entries: [M3UEntry], playlistId: UUID) -> [IPTVChannel] {
        var map: [String: IPTVChannel] = [:]
        var order: [String] = []

        for entry in entries {
            let identity = identityKey(for: entry)
            var source = IPTVSource(
                streamURLString: entry.streamURL.absoluteString,
                name: sourceLabel(for: entry),
                quality: inferQuality(from: entry),
                headers: entry.headers
            )

            if var existing = map[identity] {
                if !existing.sources.contains(where: { $0.streamURLString == source.streamURLString }) {
                    // When becoming multi-source, label by host index
                    if existing.sources.count == 1,
                       let firstURL = URL(string: existing.sources[0].streamURLString) {
                        existing.sources[0].name = "源1 · \(firstURL.host ?? existing.sources[0].streamURLString)"
                    }
                    source.name = sourceLabel(for: entry, index: existing.sources.count + 1)
                    existing.sources.append(source)
                }
                if existing.logoURLString == nil { existing.logoURLString = entry.tvgLogo }
                if existing.group == nil { existing.group = entry.groupTitle }
                if existing.tvgID == nil { existing.tvgID = entry.tvgID }
                if existing.language == nil { existing.language = entry.language }
                if existing.country == nil { existing.country = entry.country }
                map[identity] = existing
            } else {
                let channel = IPTVChannel(
                    id: identity,
                    name: displayName(for: entry),
                    logoURLString: entry.tvgLogo,
                    group: entry.groupTitle,
                    tvgID: entry.tvgID,
                    language: entry.language,
                    country: entry.country,
                    sources: [source],
                    playlistId: playlistId
                )
                map[identity] = channel
                order.append(identity)
            }
        }

        return order.compactMap { map[$0] }
    }

    /// Channel identity ignores `tvg-id` entirely (lists often give each URL a unique id).
    /// 1) exact `tvg-name` → 2) exact display name → 3) stream URL.
    static func identityKey(for entry: M3UEntry) -> String {
        if let name = entry.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "tvgn:" + name
        }
        let display = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty {
            return "name:" + display
        }
        return "url:" + entry.streamURL.absoluteString
    }

    static func displayName(for entry: M3UEntry) -> String {
        if let tvg = entry.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines), !tvg.isEmpty {
            return tvg
        }
        let n = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return "Channel"
    }

    static func sourceLabel(for entry: M3UEntry, index: Int? = nil) -> String {
        let host = entry.streamURL.host ?? entry.streamURL.absoluteString
        if let index {
            return "源\(index) · \(host)"
        }
        return host
    }

    static func inferQuality(from entry: M3UEntry) -> IPTVStreamQuality {
        let blob = (entry.name + " " + (entry.tvgName ?? "") + " " + entry.streamURL.absoluteString).lowercased()
        if blob.contains("4k") || blob.contains("uhd") || blob.contains("2160") { return .uhd }
        if blob.contains("1080") || blob.contains("fhd") || blob.contains("full hd") { return .fullHD }
        if blob.contains("720") || blob.contains(" hd") || blob.hasSuffix("hd") { return .hd }
        if blob.contains("480") || blob.contains("576") || blob.contains("sd") { return .sd }
        return .unknown
    }
}
