import Foundation

/// Aggregates M3U entries into channels vs sources.
///
/// Channel key (default): `normalize(group) + "|" + normalize(tvg-name ?? display name)`.
/// `tvg-id` is never the channel key. Kept only when consistent within channel and unique globally.
enum ChannelNormalizer {
    struct Options: Sendable {
        /// When true, key ignores group (same name merges across groups). Default false.
        var mergeAcrossGroups: Bool = false
    }

    static func channels(
        from entries: [M3UEntry],
        playlistId: UUID,
        options: Options = Options()
    ) -> [IPTVChannel] {
        var order: [String] = []
        var buckets: [String: [M3UEntry]] = [:]

        for entry in entries {
            let key = channelKey(for: entry, options: options)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key, default: []].append(entry)
        }

        var draft: [(key: String, channel: IPTVChannel, tvgIds: [String])] = []
        for key in order {
            let group = buckets[key] ?? []
            guard let first = group.first else { continue }

            var sources: [IPTVSource] = []
            var seenURL = Set<String>()
            var logo: String?
            var collectedIDs: [String] = []

            for (idx, entry) in group.enumerated() {
                let urlStr = entry.streamURL.absoluteString
                guard !seenURL.contains(urlStr) else { continue }
                seenURL.insert(urlStr)

                if logo == nil, let l = entry.tvgLogo, !l.isEmpty { logo = l }
                if let id = entry.tvgID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                    collectedIDs.append(id)
                }

                sources.append(
                    IPTVSource(
                        streamURLString: urlStr,
                        name: sourceLabel(entry: entry, index: idx + 1, totalHint: group.count),
                        quality: inferQuality(from: entry),
                        headers: entry.headers
                    )
                )
            }
            guard !sources.isEmpty else { continue }

            if sources.count > 1 {
                for i in sources.indices {
                    let host = URL(string: sources[i].streamURLString)?.host
                        ?? sources[i].streamURLString
                    sources[i].name = "源\(i + 1) · \(host)"
                }
            }

            let channel = IPTVChannel(
                id: key,
                name: displayName(for: first),
                logoURLString: logo,
                group: first.groupTitle,
                tvgID: nil,
                language: first.language,
                country: first.country,
                sources: sources,
                playlistId: playlistId
            )
            draft.append((key, channel, collectedIDs))
        }

        // Trusted tvg-id pass
        var idOwners: [String: Set<String>] = [:]
        for item in draft {
            let unique = Set(item.tvgIds)
            guard unique.count == 1, let only = unique.first else { continue }
            if item.tvgIds.allSatisfy({ $0 == only }) {
                idOwners[only, default: []].insert(item.key)
            }
        }
        let trusted = Set(idOwners.compactMap { id, keys in keys.count == 1 ? id : nil })

        return draft.map { item in
            var ch = item.channel
            let unique = Set(item.tvgIds)
            if unique.count == 1, let only = unique.first, trusted.contains(only) {
                ch.tvgID = only
            }
            return ch
        }
    }

    static func channelKey(for entry: M3UEntry, options: Options = Options()) -> String {
        let nameRaw = entry.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = normalize(nameRaw.flatMap { $0.isEmpty ? nil : $0 } ?? entry.name)
        if options.mergeAcrossGroups {
            return "n:" + name
        }
        let group = normalize(entry.groupTitle ?? "")
        return "g:" + group + "|n:" + name
    }

    /// NFKC → trim → collapse whitespace → lowercase.
    static func normalize(_ raw: String) -> String {
        let nfkc = raw.precomposedStringWithCompatibilityMapping
        let trimmed = nfkc.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.lowercased()
    }

    static func displayName(for entry: M3UEntry) -> String {
        if let tvg = entry.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines), !tvg.isEmpty {
            return tvg
        }
        let n = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Channel" : n
    }

    private static func sourceLabel(entry: M3UEntry, index: Int, totalHint: Int) -> String {
        let host = entry.streamURL.host ?? entry.streamURL.absoluteString
        if totalHint > 1 { return "源\(index) · \(host)" }
        return host
    }

    static func inferQuality(from entry: M3UEntry) -> IPTVStreamQuality {
        let blob = (entry.name + " " + (entry.tvgName ?? "") + " " + entry.streamURL.absoluteString)
            .lowercased()
        if blob.contains("4k") || blob.contains("uhd") || blob.contains("2160") { return .uhd }
        if blob.contains("1080") || blob.contains("fhd") || blob.contains("full hd") { return .fullHD }
        if blob.contains("720") || blob.contains(" hd") || blob.hasSuffix("hd") { return .hd }
        if blob.contains("480") || blob.contains("576") || blob.contains("sd") { return .sd }
        return .unknown
    }

    static func identityKey(for entry: M3UEntry) -> String {
        channelKey(for: entry, options: Options())
    }
}
