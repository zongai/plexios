import Foundation

enum SourceSelectionEngine {
    /// Estimated network throughput in Mbps (nil = unknown).
    static func select(
        from sources: [IPTVSource],
        preferred: IPTVStreamQuality,
        excluding: Set<UUID> = [],
        estimatedThroughputMbps: Double? = nil
    ) -> IPTVSource? {
        let candidates = sources.filter { !excluding.contains($0.id) && $0.streamURL != nil }
        guard !candidates.isEmpty else { return sources.first { $0.streamURL != nil } }

        let ranked = candidates.sorted { a, b in
            score(a, preferred: preferred, throughputMbps: estimatedThroughputMbps)
                > score(b, preferred: preferred, throughputMbps: estimatedThroughputMbps)
        }
        return ranked.first
    }

    /// Suggest a lower quality source when throughput is insufficient or buffering is sustained.
    static func suggestDowngrade(
        from sources: [IPTVSource],
        current: IPTVSource,
        excluding: Set<UUID>,
        estimatedThroughputMbps: Double?
    ) -> IPTVSource? {
        let lower = sources.filter {
            !excluding.contains($0.id)
                && $0.id != current.id
                && $0.streamURL != nil
                && $0.quality.sortRank < current.quality.sortRank
        }
        guard !lower.isEmpty else {
            return select(from: sources, preferred: .lowest, excluding: excluding.union([current.id]), estimatedThroughputMbps: estimatedThroughputMbps)
        }
        return select(from: lower, preferred: .lowest, excluding: excluding, estimatedThroughputMbps: estimatedThroughputMbps)
    }

    static func score(
        _ source: IPTVSource,
        preferred: IPTVStreamQuality,
        throughputMbps: Double? = nil
    ) -> Double {
        var s = 0.0
        let total = max(1, source.successCount + source.failureCount)
        s += Double(source.successCount) / Double(total) * 40
        s -= Double(source.failureCount) * 5

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

        if source.protocolType == .hls { s += 5 }

        // Throughput-aware: penalize sources that likely need more bandwidth than available.
        if let mbps = throughputMbps, mbps > 0 {
            let need = estimatedNeedMbps(source.quality)
            if mbps < need * 0.85 {
                s -= 35
            } else if mbps < need * 1.2 {
                s -= 10
            } else {
                s += 8
            }
        }
        return s
    }

    /// Rough bitrate need by quality tier (Mbps).
    static func estimatedNeedMbps(_ quality: IPTVStreamQuality) -> Double {
        switch quality {
        case .unknown: return 4
        case .lowest: return 1
        case .sd: return 2.5
        case .hd: return 5
        case .fullHD: return 8
        case .uhd: return 20
        case .highest: return 12
        }
    }
}
