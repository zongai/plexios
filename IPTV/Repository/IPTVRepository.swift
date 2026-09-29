import Foundation

/// Thread-safe IPTV data store: playlists, channels, favorites, cache.
actor IPTVRepository {
    static let shared = IPTVRepository()

    private let defaults = UserDefaults.standard
    private let maxPlaylistBytes = 15 * 1024 * 1024 // 15 MB

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

    // MARK: - Fetch & parse

    @discardableResult
    func refreshPlaylist(_ playlist: IPTVPlaylist) async throws -> IPTVPlaylist {
        guard let url = playlist.url else { throw IPTVError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("application/vnd.apple.mpegurl, audio/mpegurl, application/x-mpegURL, text/plain, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw IPTVError.downloadFailed("HTTP \(http.statusCode)")
        }
        if data.count > maxPlaylistBytes {
            throw IPTVError.playlistTooLarge
        }

        let parsed = try M3UParser.parse(data: data)
        guard !parsed.entries.isEmpty else { throw IPTVError.emptyPlaylist }

        let channels = ChannelNormalizer.channels(from: parsed.entries, playlistId: playlist.id)
        // Only replace cache after successful parse
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

    func recordSourceSuccess(channelId: String, sourceId: UUID) {
        updateSourceStats(channelId: channelId, sourceId: sourceId) { src in
            src.successCount += 1
            src.lastSuccess = Date()
        }
    }

    func recordSourceFailure(channelId: String, sourceId: UUID) {
        updateSourceStats(channelId: channelId, sourceId: sourceId) { src in
            src.failureCount += 1
            src.lastFailure = Date()
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
