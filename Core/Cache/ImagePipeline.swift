import Foundation
import UIKit

/// Image loading with memory + disk cache, deduplication, downsampling,
/// prefetch, memory-pressure handling, and disk budget eviction.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL
    private let session: URLSession
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let maxDiskBytes: Int
    private var memoryWarningObserver: NSObjectProtocol?

    init(
        session: URLSession? = nil,
        maxDiskBytes: Int = 200 * 1024 * 1024 // 200 MB
    ) {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 0)
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config)
        self.maxDiskBytes = maxDiskBytes

        memoryCache.countLimit = 250
        memoryCache.totalCostLimit = 100 * 1024 * 1024

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = caches.appendingPathComponent("PlexImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // Memory warnings observed on main; hop into actor.
        Task { await self.installMemoryWarningObserver() }
    }

    // MARK: - Public API

    func image(for url: URL, pointSize: CGSize? = nil) async -> UIImage? {
        let key = cacheKey(url: url, pointSize: pointSize)

        if let mem = memoryCache.object(forKey: key as NSString) {
            return mem
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            if let disk = self.loadFromDisk(key: key) {
                self.memoryCache.setObject(disk, forKey: key as NSString, cost: disk.costEstimate)
                return disk
            }

            do {
                let (data, response) = try await self.session.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      !data.isEmpty
                else { return nil }

                // Decode off main (we're already in actor / cooperative pool)
                let image: UIImage?
                if let pointSize, pointSize.width > 0, pointSize.height > 0 {
                    image = self.downsample(data: data, pointSize: pointSize)
                } else {
                    image = UIImage(data: data)
                }

                guard let image else { return nil }
                self.saveToDisk(data: data, key: key)
                self.memoryCache.setObject(image, forKey: key as NSString, cost: image.costEstimate)
                await self.enforceDiskBudgetIfNeeded()
                return image
            } catch {
                return nil
            }
        }

        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// Prefetch images without blocking UI; ignores results.
    func prefetch(urls: [URL], pointSize: CGSize? = nil) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for url in urls.prefix(20) {
                    group.addTask {
                        _ = await self.image(for: url, pointSize: pointSize)
                    }
                }
            }
        }
    }

    func cancelAll() {
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
    }

    func clearMemory() {
        memoryCache.removeAllObjects()
    }

    func clearDisk() {
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    func clearAll() {
        clearMemory()
        clearDisk()
        cancelAll()
    }

    func diskUsageBytes() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + size
        }
    }

    // MARK: - Memory pressure

    private func installMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleMemoryWarning() }
        }
    }

    private func handleMemoryWarning() {
        memoryCache.removeAllObjects()
        // Cancel non-essential in-flight
        cancelAll()
    }

    // MARK: - Disk

    private func loadFromDisk(key: String) -> UIImage? {
        let file = diskCacheURL.appendingPathComponent(key.sha256)
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Touch for LRU-ish eviction by modification date
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: file.path
        )
        return UIImage(data: data)
    }

    private func saveToDisk(data: Data, key: String) {
        let file = diskCacheURL.appendingPathComponent(key.sha256)
        try? data.write(to: file, options: .atomic)
    }

    private func enforceDiskBudgetIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var total = 0
        var entries: [(url: URL, size: Int, date: Date)] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let date = values?.contentModificationDate ?? .distantPast
            total += size
            entries.append((url, size, date))
        }

        guard total > maxDiskBytes else { return }

        // Evict least-recently-touched first
        entries.sort { $0.date < $1.date }
        for entry in entries {
            guard total > maxDiskBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private func cacheKey(url: URL, pointSize: CGSize?) -> String {
        if let s = pointSize {
            return "\(url.absoluteString)|\(Int(s.width))x\(Int(s.height))"
        }
        return url.absoluteString
    }

    private func downsample(data: Data, pointSize: CGSize) -> UIImage? {
        // Prefer main-screen scale; fall back to 3x when called off the main actor
        let scale: CGFloat
        if Thread.isMainThread {
            scale = UIScreen.main.scale
        } else {
            scale = 3.0
        }
        let maxDim = max(pointSize.width, pointSize.height) * scale
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

private extension UIImage {
    var costEstimate: Int {
        guard let cg = cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }
}

private extension String {
    var sha256: String {
        var hash: UInt64 = 5381
        for c in utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(c) }
        return String(hash, radix: 16)
    }
}
