import Foundation

enum SourceSelectionEngine {
    /// Pick best source for preferences + simple reliability score.
    static func select(
        from sources: [IPTVSource],
        preferred: IPTVStreamQuality,
        excluding: Set<UUID> = []
    ) -> IPTVSource? {
        let candidates = sources.filter { !excluding.contains($0.id) && $0.streamURL != nil }
        guard !candidates.isEmpty else { return sources.first }

        let ranked = candidates.sorted { a, b in
            score(a, preferred: preferred) > score(b, preferred: preferred)
        }
        return ranked.first
    }

    static func score(_ source: IPTVSource, preferred: IPTVStreamQuality) -> Double {
        var s = 0.0
        // Reliability
        let total = max(1, source.successCount + source.failureCount)
        s += Double(source.successCount) / Double(total) * 40
        s -= Double(source.failureCount) * 5

        // Quality preference
        switch preferred {
        case .unknown, .highest:
            s += Double(source.quality.sortRank) * 8
        case .lowest:
            s += Double(6 - source.quality.sortRank) * 8
        default:
            let diff = abs(source.quality.sortRank - preferred.sortRank)
            s += max(0, 24 - Double(diff) * 8)
            if source.quality == preferred { s += 15 }
        }

        // Prefer HLS slightly for iOS
        if source.protocolType == .hls { s += 5 }
        return s
    }
}
