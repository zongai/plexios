import Foundation

/// Server context required for PMS calls.
struct ServerContext: Sendable {
    let baseURL: URL
    let token: String
    let machineIdentifier: String
}

// MARK: - Library

actor LibraryRepository {
    private let api: PlexAPIClient
    private let cache: ResponseCache
    private var memoryLibraries: [String: (date: Date, libraries: [PlexLibrary])] = [:]

    init(api: PlexAPIClient, cache: ResponseCache = ResponseCache(namespace: "library")) {
        self.api = api
        self.cache = cache
    }

    func libraries(context: ServerContext, force: Bool = false) async throws -> [PlexLibrary] {
        let key = "sections:\(context.machineIdentifier)"
        if !force {
            if let hit = memoryLibraries[key],
               Date().timeIntervalSince(hit.date) < CacheTTL.libraries {
                return hit.libraries
            }
            if let cached: [PlexLibrary] = await cache.value(forKey: key) {
                memoryLibraries[key] = (Date(), cached)
                return cached
            }
        }

        let list = try await api.fetchLibrarySections(baseURL: context.baseURL, token: context.token)
        memoryLibraries[key] = (Date(), list)
        await cache.store(list, forKey: key, ttl: CacheTTL.libraries)
        return list
    }

    func items(
        sectionKey: String,
        context: ServerContext,
        start: Int = 0,
        size: Int = 50,
        force: Bool = false
    ) async throws -> [PlexMetadata] {
        let key = "all:\(context.machineIdentifier):\(sectionKey):\(start):\(size)"
        if !force, let cached: [PlexMetadata] = await cache.value(forKey: key) {
            return cached
        }

        let page = try await api.fetchLibraryAll(
            sectionKey: sectionKey,
            baseURL: context.baseURL,
            token: context.token,
            start: start,
            size: size
        )
        await cache.store(page, forKey: key, ttl: CacheTTL.libraryPage)
        return page
    }

    func invalidate(machineIdentifier: String) async {
        memoryLibraries = memoryLibraries.filter { !$0.key.contains(machineIdentifier) }
        // Disk keys are hashed; full clear of namespace on server switch is simplest.
        await cache.removeAll()
    }
}

// MARK: - Hub / Home

actor HubRepository {
    private let api: PlexAPIClient
    private let cache: ResponseCache

    init(api: PlexAPIClient, cache: ResponseCache = ResponseCache(namespace: "hubs")) {
        self.api = api
        self.cache = cache
    }

    func homeHubs(context: ServerContext, force: Bool = false) async throws -> [PlexHub] {
        let key = "home:\(context.machineIdentifier)"
        if !force, let cached: [PlexHub] = await cache.value(forKey: key) {
            return cached
        }

        let hubs = try await api.fetchHomeHubs(baseURL: context.baseURL, token: context.token)
        await cache.store(hubs, forKey: key, ttl: CacheTTL.hubs)
        return hubs
    }

    func invalidate(machineIdentifier: String) async {
        await cache.remove(forKey: "home:\(machineIdentifier)")
    }
}

// MARK: - Metadata

actor MetadataRepository {
    private let api: PlexAPIClient
    private let cache: ResponseCache

    init(api: PlexAPIClient, cache: ResponseCache = ResponseCache(namespace: "metadata")) {
        self.api = api
        self.cache = cache
    }

    func metadata(ratingKey: String, context: ServerContext, force: Bool = false) async throws -> PlexMetadata {
        let key = "meta:\(context.machineIdentifier):\(ratingKey)"
        if !force, let cached: PlexMetadata = await cache.value(forKey: key) {
            return cached
        }

        let item = try await api.fetchMetadata(
            ratingKey: ratingKey,
            baseURL: context.baseURL,
            token: context.token
        )
        await cache.store(item, forKey: key, ttl: CacheTTL.metadata)
        return item
    }

    func children(ratingKey: String, context: ServerContext) async throws -> [PlexMetadata] {
        let key = "children:\(context.machineIdentifier):\(ratingKey)"
        if let cached: [PlexMetadata] = await cache.value(forKey: key) {
            return cached
        }
        let items = try await api.fetchChildren(
            ratingKey: ratingKey,
            baseURL: context.baseURL,
            token: context.token
        )
        await cache.store(items, forKey: key, ttl: CacheTTL.metadata)
        return items
    }

    func invalidate(ratingKey: String, machineIdentifier: String) async {
        await cache.remove(forKey: "meta:\(machineIdentifier):\(ratingKey)")
        await cache.remove(forKey: "children:\(machineIdentifier):\(ratingKey)")
    }
}

// MARK: - Search

actor SearchRepository {
    private let api: PlexAPIClient
    private let cache: ResponseCache

    init(api: PlexAPIClient, cache: ResponseCache = ResponseCache(namespace: "search")) {
        self.api = api
        self.cache = cache
    }

    func search(query: String, context: ServerContext) async throws -> [PlexHub] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        try Task.checkCancellation()

        let key = "q:\(context.machineIdentifier):\(trimmed.lowercased())"
        if let cached: [PlexHub] = await cache.value(forKey: key) {
            try Task.checkCancellation()
            return cached
        }

        let hubs = try await api.search(query: trimmed, baseURL: context.baseURL, token: context.token)
        try Task.checkCancellation()
        await cache.store(hubs, forKey: key, ttl: CacheTTL.search)
        return hubs
    }
}

// MARK: - Collections / Playlists / Favorites

actor CollectionsRepository {
    private let api: PlexAPIClient
    private let cache: ResponseCache

    init(api: PlexAPIClient, cache: ResponseCache = ResponseCache(namespace: "collections")) {
        self.api = api
        self.cache = cache
    }

    func collections(context: ServerContext, force: Bool = false) async throws -> [PlexMetadata] {
        let key = "all:\(context.machineIdentifier)"
        if !force, let cached: [PlexMetadata] = await cache.value(forKey: key) {
            return cached
        }
        var list = try await api.fetchCollections(baseURL: context.baseURL, token: context.token)
        if list.isEmpty {
            // Aggregate from each library section
            let sections = try await api.fetchLibrarySections(baseURL: context.baseURL, token: context.token)
            var aggregated: [PlexMetadata] = []
            for section in sections {
                let part = (try? await api.fetchSectionCollections(
                    sectionKey: section.key,
                    baseURL: context.baseURL,
                    token: context.token
                )) ?? []
                aggregated.append(contentsOf: part)
            }
            list = aggregated
        }
        await cache.store(list, forKey: key, ttl: CacheTTL.libraries)
        return list
    }

    func children(ratingKey: String, context: ServerContext) async throws -> [PlexMetadata] {
        try await api.fetchChildren(ratingKey: ratingKey, baseURL: context.baseURL, token: context.token)
    }
}

actor PlaylistsRepository {
    private let api: PlexAPIClient
    private let cache: ResponseCache

    init(api: PlexAPIClient, cache: ResponseCache = ResponseCache(namespace: "playlists")) {
        self.api = api
        self.cache = cache
    }

    func playlists(context: ServerContext, force: Bool = false) async throws -> [PlexMetadata] {
        let key = "all:\(context.machineIdentifier)"
        if !force, let cached: [PlexMetadata] = await cache.value(forKey: key) {
            return cached
        }
        let list = try await api.fetchPlaylists(baseURL: context.baseURL, token: context.token)
        await cache.store(list, forKey: key, ttl: CacheTTL.libraries)
        return list
    }

    func items(ratingKey: String, context: ServerContext) async throws -> [PlexMetadata] {
        try await api.fetchPlaylistItems(ratingKey: ratingKey, baseURL: context.baseURL, token: context.token)
    }
}

actor FavoritesRepository {
    private let api: PlexAPIClient

    init(api: PlexAPIClient) {
        self.api = api
    }

    func setFavorite(_ isFavorite: Bool, key: String, context: ServerContext) async throws {
        try await api.rate(key: key, rating: isFavorite ? 10 : 0, baseURL: context.baseURL, token: context.token)
    }
}
