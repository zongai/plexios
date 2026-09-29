import Foundation

actor EPGRepository {
    static let shared = EPGRepository()

    private let defaults = UserDefaults.standard
    private let maxEPGBytes = 25 * 1024 * 1024
    private var memoryIndex = EPGChannelIndex()
    private var lastFetch: [String: Date] = [:] // epgURL → time

    private enum Keys {
        static let cachePrefix = "iptv.epg.cache."
        static let metaPrefix = "iptv.epg.meta."
    }

    func index() -> EPGChannelIndex { memoryIndex }

    func currentProgram(tvgID: String?) -> EPGProgram? {
        guard let id = tvgID, !id.isEmpty else { return nil }
        return memoryIndex.current(channelID: id)
    }

    func nextProgram(tvgID: String?) -> EPGProgram? {
        guard let id = tvgID, !id.isEmpty else { return nil }
        return memoryIndex.next(channelID: id)
    }

    /// Load from disk cache into memory (call on app start / IPTV open).
    func warmCache(for epgURLs: [URL]) {
        var map: [String: [EPGProgram]] = memoryIndex.programsByChannel
        for url in epgURLs {
            let key = Keys.cachePrefix + url.absoluteString.sha256Prefix()
            guard let data = defaults.data(forKey: key),
                  let programs = try? JSONDecoder().decode([EPGProgram].self, from: data) else {
                continue
            }
            for p in programs {
                map[p.channelID, default: []].append(p)
            }
        }
        for (k, v) in map {
            map[k] = v.sorted { $0.startTime < $1.startTime }
        }
        memoryIndex = EPGChannelIndex(programsByChannel: map)
    }

    @discardableResult
    func refresh(url: URL, force: Bool = false) async throws -> Int {
        let key = url.absoluteString
        if !force, let last = lastFetch[key], Date().timeIntervalSince(last) < 3600 {
            return memoryIndex.programsByChannel.values.reduce(0) { $0 + $1.count }
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/xml, text/xml, application/gzip, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await IPTVNetwork.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw IPTVError.downloadFailed("EPG HTTP \(http.statusCode)")
        }
        if data.count > maxEPGBytes {
            throw IPTVError.playlistTooLarge
        }

        let programs = try XMLTVParser.parse(data: data)
        // Persist
        let cacheKey = Keys.cachePrefix + url.absoluteString.sha256Prefix()
        if let encoded = try? JSONEncoder().encode(programs) {
            defaults.set(encoded, forKey: cacheKey)
        }
        lastFetch[key] = Date()

        // Merge into index
        var map = memoryIndex.programsByChannel
        // Replace programs for channels present in this file
        let channelIds = Set(programs.map(\.channelID))
        for id in channelIds {
            map[id] = []
        }
        for p in programs {
            map[p.channelID, default: []].append(p)
        }
        for id in channelIds {
            map[id] = map[id]?.sorted { $0.startTime < $1.startTime }
        }
        memoryIndex = EPGChannelIndex(programsByChannel: map)
        return programs.count
    }

    func matchTvgID(for channel: IPTVChannel) -> String? {
        if let id = channel.tvgID, !id.isEmpty { return id }
        // Fallback: normalized channel name (when tvg-id is untrusted / ignored)
        let name = ChannelNormalizer.normalize(channel.name)
        if !name.isEmpty, memoryIndex.programsByChannel[name] != nil {
            return name
        }
        return nil
    }
}

private extension String {
    func sha256Prefix() -> String {
        // Lightweight stable key without CryptoKit dependency issues
        var hash: UInt64 = 5381
        for c in utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(c)
        }
        return String(hash, radix: 16)
    }
}
