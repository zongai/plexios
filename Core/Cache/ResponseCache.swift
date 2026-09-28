import Foundation

/// Generic TTL cache with memory + optional disk persistence for Codable values.
actor ResponseCache {
    struct Entry<T> {
        let value: T
        let storedAt: Date
        let ttl: TimeInterval

        var isExpired: Bool {
            Date().timeIntervalSince(storedAt) >= ttl
        }
    }

    private var memory: [String: (storedAt: Date, ttl: TimeInterval, data: Data)] = [:]
    private let diskURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxMemoryEntries: Int

    init(namespace: String = "api", maxMemoryEntries: Int = 256) {
        self.maxMemoryEntries = maxMemoryEntries
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskURL = caches.appendingPathComponent("PlexResponseCache/\(namespace)", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: true)
    }

    func value<T: Codable>(forKey key: String, as type: T.Type = T.self) -> T? {
        if let mem = memory[key], Date().timeIntervalSince(mem.storedAt) < mem.ttl {
            return try? decoder.decode(T.self, from: mem.data)
        }
        // Disk
        let file = diskURL.appendingPathComponent(key.stableHash)
        guard
            let raw = try? Data(contentsOf: file),
            let envelope = try? decoder.decode(DiskEnvelope.self, from: raw),
            Date().timeIntervalSince(envelope.storedAt) < envelope.ttl,
            let value = try? decoder.decode(T.self, from: envelope.payload)
        else {
            return nil
        }
        // Promote to memory
        memory[key] = (envelope.storedAt, envelope.ttl, envelope.payload)
        return value
    }

    func store<T: Codable>(_ value: T, forKey key: String, ttl: TimeInterval) {
        guard let data = try? encoder.encode(value) else { return }
        let now = Date()
        memory[key] = (now, ttl, data)
        trimMemoryIfNeeded()

        let envelope = DiskEnvelope(storedAt: now, ttl: ttl, payload: data)
        if let raw = try? encoder.encode(envelope) {
            let file = diskURL.appendingPathComponent(key.stableHash)
            try? raw.write(to: file, options: .atomic)
        }
    }

    func remove(forKey key: String) {
        memory.removeValue(forKey: key)
        let file = diskURL.appendingPathComponent(key.stableHash)
        try? FileManager.default.removeItem(at: file)
    }

    func removeAll() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: diskURL)
        try? FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: true)
    }

    private func trimMemoryIfNeeded() {
        guard memory.count > maxMemoryEntries else { return }
        let sorted = memory.sorted { $0.value.storedAt < $1.value.storedAt }
        let dropCount = memory.count - maxMemoryEntries
        for i in 0..<dropCount {
            memory.removeValue(forKey: sorted[i].key)
        }
    }

    private struct DiskEnvelope: Codable {
        let storedAt: Date
        let ttl: TimeInterval
        let payload: Data
    }
}

private extension String {
    var stableHash: String {
        var hash: UInt64 = 5381
        for c in utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(c) }
        return String(hash, radix: 16)
    }
}

// MARK: - Policy

enum CacheTTL {
    static let libraries: TimeInterval = 120
    static let hubs: TimeInterval = 60
    static let metadata: TimeInterval = 300
    static let libraryPage: TimeInterval = 90
    static let search: TimeInterval = 30
}
