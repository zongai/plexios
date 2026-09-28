import SwiftUI

/// Prefetches poster URLs for upcoming grid/rail cells.
enum ImagePrefetch {
    static func posters(
        for items: [PlexMetadata],
        baseURL: URL?,
        token: String?,
        pointSize: CGSize = CGSize(width: 120, height: 180)
    ) {
        let urls = items.compactMap { item -> URL? in
            PlexImageURL.resolve(
                path: item.posterPath(),
                baseURL: baseURL,
                token: token,
                width: Int(pointSize.width * 2),
                height: Int(pointSize.height * 2)
            )
        }
        Task {
            await ImagePipeline.shared.prefetch(urls: urls, pointSize: pointSize)
        }
    }
}

/// Clears image + response caches from Settings.
enum CacheMaintenance {
    @MainActor
    static func clearAll() async {
        await ImagePipeline.shared.clearAll()
        // Response caches are per-repository; recreate is handled by user restart
        // or explicit repository invalidation from AppEnvironment if wired.
    }

    static func imageDiskUsageMB() async -> Double {
        let bytes = await ImagePipeline.shared.diskUsageBytes()
        return Double(bytes) / (1024 * 1024)
    }
}
