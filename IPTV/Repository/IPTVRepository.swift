import Foundation

/// Thread-safe IPTV data store: playlists, channels, favorites, cache.
actor IPTVRepository {
    static let shared = IPTVRepository()

    private let defaults = UserDefaults.standard
    private let maxPlaylistBytes = M3UStreamingParser.maxBytes

    private enum Keys {
        static let playlists = "iptv.playlists"
        static let channelsPrefix = "iptv.channels."
        static let prefs = "iptv.preferences"
    }

    // MARK: - Preferences

    func preferences() -> IPTVPreferences {
        guard let data = defaults.data(forKey: Keys.prefs),
              let p = try? JSONDecoder().decode(IPTVPreferences.self, from: data) else {
            return .default
        }
        return p
    }

    func savePreferences(_ prefs: IPTVPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: Keys.prefs)
        }
    }

    func toggleFavorite(channelId: String) {
        var p = preferences()
        if let i = p.favoriteChannelIds.firstIndex(of: channelId) {
            p.favoriteChannelIds.remove(at: i)
        } else {
            p.favoriteChannelIds.append(channelId)
        }
        savePreferences(p)
    }

    // MARK: - Playlists

    func playlists() -> [IPTVPlaylist] {
        guard let data = defaults.data(forKey: Keys.playlists),
              let list = try? JSONDecoder().decode([IPTVPlaylist].self, from: data) else {
            return []
        }
        return list
    }

    func savePlaylists(_ list: [IPTVPlaylist]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Keys.playlists)
        }
    }

    func addPlaylist(_ playlist: IPTVPlaylist) {
        var list = playlists()
        list.append(playlist)
        savePlaylists(list)
    }

    func updatePlaylist(_ playlist: IPTVPlaylist) {
        var list = playlists()
        if let i = list.firstIndex(where: { $0.id == playlist.id }) {
            list[i] = playlist
            savePlaylists(list)
        }
    }

    func deletePlaylist(id: UUID) {
        var list = playlists()
        list.removeAll { $0.id == id }
        savePlaylists(list)
        defaults.removeObject(forKey: Keys.channelsPrefix + id.uuidString)
    }

    // MARK: - Channels

    func channels(for playlistId: UUID) -> [IPTVChannel] {
        guard let data = defaults.data(forKey: Keys.channelsPrefix + playlistId.uuidString),
              let list = try? JSONDecoder().decode([IPTVChannel].self, from: data) else {
            return []
        }
        return list
    }

    func allEnabledChannels() -> [IPTVChannel] {
        playlists().filter(\.enabled).flatMap { channels(for: $0.id) }
    }

    private func saveChannels(_ channels: [IPTVChannel], playlistId: UUID) {
        if let data = try? JSONEncoder().encode(channels) {
            defaults.set(data, forKey: Keys.channelsPrefix + playlistId.uuidString)
        }
    }

    /// All EPG candidate URLs (global + per-playlist).
    func epgURLs() -> [URL] {
        var urls: [URL] = []
        if let g = preferences().globalEPGURL {
            urls.append(g)
        }
        for pl in playlists() where pl.enabled {
            if let u = pl.epgURL { urls.append(u) }
        }
        // Unique by absoluteString
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    // MARK: - Fetch & parse (streaming line parser)

    @discardableResult
    func refreshPlaylist(_ playlist: IPTVPlaylist) async throws -> IPTVPlaylist {
        guard let url = playlist.url else { throw IPTVError.invalidURL }

        let parsed: M3UParseResult
        do {
            parsed = try await M3UStreamingParser.downloadAndParse(url: url)
        } catch {
            // Keep existing channels on failure
            throw error
        }
        guard !parsed.entries.isEmpty else { throw IPTVError.emptyPlaylist }

        let channels = ChannelNormalizer.channels(from: parsed.entries, playlistId: playlist.id)
        saveChannels(channels, playlistId: playlist.id)

        var updated = playlist
        updated.lastUpdated = Date()
        updated.channelCount = channels.count
        if updated.epgURLString == nil, let epg = parsed.epgURL {
            updated.epgURLString = epg.absoluteString
        }
        updatePlaylist(updated)
        return updated
    }

    /// Refresh all EPG sources for enabled playlists + global.
    func refreshAllEPG(force: Bool = false) async {
        for url in epgURLs() {
            _ = try? await EPGRepository.shared.refresh(url: url, force: force)
        }
    }


    func applySourceUpdate(channelId: String, source: IPTVSource) {
        updateSourceStats(channelId: channelId, sourceId: source.id) { src in
            src = source
        }
    }

    /// Probe sources that are due; persist results. Returns updated channel.
    func probeChannelSources(_ channel: IPTVChannel, limit: Int = 3) async -> IPTVChannel {
        let prefs = preferences()
        guard prefs.autoProbeSources else { return channel }
        var ch = channel
        let updated = await SourceProbeService.shared.probeIfNeeded(sources: ch.sources, prefs: prefs, limit: limit)
        ch.sources = updated
        // Persist each changed source
        for src in updated {
            applySourceUpdate(channelId: ch.id, source: src)
        }
        return ch
    }

    func recordSourceSuccess(channelId: String, sourceId: UUID) {
        updateSourceStats(channelId: channelId, sourceId: sourceId) { src in
            src.successCount += 1
            src.lastSuccess = Date()
        }
    }

    func recordSourceFailure(channelId: String, sourceId: UUID) {
        let prefs = preferences()
        let cooldown = max(15, prefs.probeFailureCooldownMinutes) * 60
        updateSourceStats(channelId: channelId, sourceId: sourceId) { src in
            src.failureCount += 1
            src.lastFailure = Date()
            src.lastProbeAt = Date()
            // Ignore until next allowed test window
            src.disabledUntil = Date().addingTimeInterval(cooldown)
        }
    }

    private func updateSourceStats(channelId: String, sourceId: UUID, mutate: (inout IPTVSource) -> Void) {
        for pl in playlists() {
            var chs = channels(for: pl.id)
            guard let ci = chs.firstIndex(where: { $0.id == channelId }),
                  let si = chs[ci].sources.firstIndex(where: { $0.id == sourceId }) else { continue }
            mutate(&chs[ci].sources[si])
            saveChannels(chs, playlistId: pl.id)
            return
        }
    }
}
