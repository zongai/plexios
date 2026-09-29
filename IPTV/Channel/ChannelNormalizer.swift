import Foundation

enum ChannelNormalizer {
    /// Build a stable channel id and merge entries that clearly belong together.
    static func channels(from entries: [M3UEntry], playlistId: UUID) -> [IPTVChannel] {
        var map: [String: IPTVChannel] = [:]
        var order: [String] = []

        for entry in entries {
            let identity = identityKey(for: entry)
            let quality = inferQuality(from: entry)
            let source = IPTVSource(
                streamURLString: entry.streamURL.absoluteString,
                name: entry.name,
                quality: quality,
                headers: entry.headers
            )

            if var existing = map[identity] {
                // Avoid duplicate identical stream URLs
                if !existing.sources.contains(where: { $0.streamURLString == source.streamURLString }) {
                    existing.sources.append(source)
                }
                // Prefer richer metadata
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

    /// Prefer tvg-id; else normalized tvg-name; else normalized display name.
    /// Do not merge on weak prefixes (e.g. all "CCTV*").
    static func identityKey(for entry: M3UEntry) -> String {
        if let id = entry.tvgID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return "tvg:" + id.lowercased()
        }
        if let name = entry.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "tvgn:" + normalizeName(name)
        }
        return "name:" + normalizeName(entry.name)
    }

    static func normalizeName(_ raw: String) -> String {
        var s = raw.lowercased()
        // Strip common quality tags but keep channel numbers
        let tags = [" fhd", " uhd", " 4k", " hd", " sd", " hevc", " h265", " h264"]
        for t in tags {
            s = s.replacingOccurrences(of: t, with: "")
        }
        // Remove punctuation except digits/letters
        s = s.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }.map(String.init).joined()
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayName(for entry: M3UEntry) -> String {
        let n = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return entry.tvgName ?? "Channel"
    }

    static func inferQuality(from entry: M3UEntry) -> IPTVStreamQuality {
        let blob = (entry.name + " " + (entry.tvgName ?? "")).lowercased()
        if blob.contains("4k") || blob.contains("uhd") || blob.contains("2160") { return .uhd }
        if blob.contains("1080") || blob.contains("fhd") || blob.contains("full hd") { return .fullHD }
        if blob.contains("720") || blob.contains(" hd") || blob.hasSuffix("hd") { return .hd }
        if blob.contains("480") || blob.contains("576") || blob.contains("sd") { return .sd }
        return .unknown
    }
}
