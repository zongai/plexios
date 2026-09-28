import Foundation

/// Unified client for plex.tv and PMS endpoints.
/// Injects client identity + token headers; decodes JSON; maps errors.
actor PlexAPIClient {
    private let http: HTTPClient
    private let identity: ClientIdentity
    private let logger: LogRouter
    private let decoder: JSONDecoder

    private let plexTVBase = URL(string: "https://plex.tv")!
    private let clientsPlexTVBase = URL(string: "https://clients.plex.tv")!

    init(http: HTTPClient, identity: ClientIdentity, logger: LogRouter) {
        self.http = http
        self.identity = identity
        self.logger = logger
        self.decoder = JSONDecoder()
    }

    // MARK: - Auth (plex.tv)

    /// Create a PIN for user sign-in at plex.tv/link.
    ///
    /// Do **not** pass `strong=true`: that returns a long (~25 char) code meant for
    /// embedded OAuth URLs (`app.plex.tv/auth#?code=…`). plex-for-kodi and the
    /// classic link page expect a short 4-character code from a non-strong PIN.
    func createPIN() async throws -> PlexPin {
        var request = try makeRequest(
            base: clientsPlexTVBase,
            path: "api/v2/pins",
            method: "POST"
        )
        applyIdentityHeaders(to: &request)
        // Prefer JSON so APIPINResponse decoding is stable
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await http.data(for: request)
        let dto = try decode(APIPINResponse.self, from: response.data)
        return PlexAPIMapper.pin(from: dto)
    }

    /// Poll PIN status; returns pin with authToken when claimed.
    func checkPIN(id: Int, code: String) async throws -> PlexPin {
        var request = try makeRequest(
            base: clientsPlexTVBase,
            path: "api/v2/pins/\(id)",
            query: [URLQueryItem(name: "code", value: code)]
        )
        applyIdentityHeaders(to: &request)

        let response = try await http.data(for: request)
        let dto = try decode(APIPINResponse.self, from: response.data)
        return PlexAPIMapper.pin(from: dto)
    }

    // MARK: - Resources (server discovery)

    func fetchServers(authToken: String) async throws -> [PlexServer] {
        var request = try makeRequest(
            base: plexTVBase,
            path: "api/v2/resources",
            query: [
                URLQueryItem(name: "includeHttps", value: "1"),
                URLQueryItem(name: "includeRelay", value: "1"),
                URLQueryItem(name: "includeIPv6", value: "1")
            ]
        )
        applyIdentityHeaders(to: &request)
        request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")

        let response = try await perform(request)
        // Resources endpoint returns a top-level JSON array
        let resources = try decoder.decode([APIResource].self, from: response.data)
        return resources.compactMap(PlexAPIMapper.server(from:))
    }

    // MARK: - PMS endpoints

    func fetchLibrarySections(baseURL: URL, token: String) async throws -> [PlexLibrary] {
        guard let url = PlexURL.join(baseURL, path: "library/sections") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        applyPMSHeaders(to: &request, token: token)

        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APILibrarySectionsContainer>.self, from: response.data)
        return (container.mediaContainer.directory ?? []).compactMap(PlexAPIMapper.library(from:))
    }

    /// Home feed — matches plex-for-kodi (`/hubs`), not `/hubs/home`.
    func fetchHomeHubs(baseURL: URL, token: String) async throws -> [PlexHub] {
        guard let url = PlexURL.join(baseURL, path: "hubs") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        applyPMSHeaders(to: &request, token: token)

        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIHubsContainer>.self, from: response.data)
        return (container.mediaContainer.hub ?? []).compactMap(PlexAPIMapper.hub(from:))
    }

    func fetchMetadata(ratingKey: String, baseURL: URL, token: String) async throws -> PlexMetadata {
        var request = try makeRequest(
            base: baseURL,
            path: "library/metadata/\(ratingKey)",
            query: [
                URLQueryItem(name: "includeMarkers", value: "1"),
                URLQueryItem(name: "includeChapters", value: "1")
            ]
        )
        applyPMSHeaders(to: &request, token: token)

        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        guard let item = (container.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:)).first else {
            throw PlexError.mediaUnavailable
        }
        return item
    }

    func fetchChildren(ratingKey: String, baseURL: URL, token: String) async throws -> [PlexMetadata] {
        guard let url = PlexURL.join(baseURL, path: "library/metadata/\(ratingKey)/children") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        applyPMSHeaders(to: &request, token: token)

        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        return (container.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:))
    }

    func fetchLibraryAll(sectionKey: String, baseURL: URL, token: String, start: Int = 0, size: Int = 50) async throws -> [PlexMetadata] {
        var request = try makeRequest(
            base: baseURL,
            path: "library/sections/\(sectionKey)/all",
            query: [
                URLQueryItem(name: "X-Plex-Container-Start", value: "\(start)"),
                URLQueryItem(name: "X-Plex-Container-Size", value: "\(size)")
            ]
        )
        applyPMSHeaders(to: &request, token: token)
        request.setValue("\(start)", forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue("\(size)", forHTTPHeaderField: "X-Plex-Container-Size")

        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        return (container.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:))
    }

    func search(query: String, baseURL: URL, token: String) async throws -> [PlexHub] {
        var request = try makeRequest(
            base: baseURL,
            path: "hubs/search",
            query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: "30")
            ]
        )
        applyPMSHeaders(to: &request, token: token)

        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIHubsContainer>.self, from: response.data)
        return (container.mediaContainer.hub ?? []).compactMap(PlexAPIMapper.hub(from:))
    }

    // MARK: - Collections / Playlists / Favorites / Related

    func fetchCollections(baseURL: URL, token: String) async throws -> [PlexMetadata] {
        var request = try makeRequest(
            base: baseURL,
            path: "library/collections",
            query: [URLQueryItem(name: "includeCollections", value: "1")]
        )
        applyPMSHeaders(to: &request, token: token)
        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        return (container.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:))
    }

    /// Fallback: per-section collections when global path is empty.
    func fetchSectionCollections(sectionKey: String, baseURL: URL, token: String) async throws -> [PlexMetadata] {
        guard let url = PlexURL.join(baseURL, path: "library/sections/\(sectionKey)/collections") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        applyPMSHeaders(to: &request, token: token)
        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        return (container.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:))
    }

    func fetchPlaylists(baseURL: URL, token: String) async throws -> [PlexMetadata] {
        guard let url = PlexURL.join(baseURL, path: "playlists") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        applyPMSHeaders(to: &request, token: token)
        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        return (container.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:))
    }

    func fetchPlaylistItems(ratingKey: String, baseURL: URL, token: String) async throws -> [PlexMetadata] {
        guard let url = PlexURL.join(baseURL, path: "playlists/\(ratingKey)/items") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        applyPMSHeaders(to: &request, token: token)
        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        return (container.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:))
    }

    /// rate=10 → favorite/thumb up; rate=0 → clear
    func rate(key: String, rating: Int, baseURL: URL, token: String) async throws {
        var request = try makeRequest(
            base: baseURL,
            path: ":/rate",
            query: [
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
                URLQueryItem(name: "rating", value: "\(rating)")
            ],
            method: "PUT"
        )
        applyPMSHeaders(to: &request, token: token)
        _ = try await perform(request, allowNon2xx: true)
    }

    func fetchRelated(ratingKey: String, baseURL: URL, token: String) async throws -> [PlexHub] {
        guard let url = PlexURL.join(baseURL, path: "hubs/metadata/\(ratingKey)/related") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        applyPMSHeaders(to: &request, token: token)
        let response = try await perform(request)
        let container = try decode(APIMediaContainer<APIHubsContainer>.self, from: response.data)
        return (container.mediaContainer.hub ?? []).compactMap(PlexAPIMapper.hub(from:))
    }

    /// Continues TV: next unwatched / next episode from metadata key.
    func fetchContinue(ratingKey: String, baseURL: URL, token: String) async throws -> PlexMetadata? {
        // Prefer `/library/metadata/{id}/continue` style when available via children of grandparent
        // Fallback: related hubs looking for "continue" / "next"
        let related = try await fetchRelated(ratingKey: ratingKey, baseURL: baseURL, token: token)
        for hub in related {
            let id = (hub.hubIdentifier ?? hub.key).lowercased()
            if id.contains("continue") || id.contains("next") || hub.title.lowercased().contains("up next") {
                if let first = hub.items.first { return first }
            }
        }
        // Episode → try next sibling via parent children
        return nil
    }

    /// Lightweight reachability + identity check.
    func probeIdentity(baseURL: URL, token: String?) async throws -> (machineIdentifier: String?, version: String?) {
        guard let url = PlexURL.join(baseURL, path: "identity") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        applyIdentityHeaders(to: &request)
        request.setValue("application/json, text/xml, */*", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }

        let response = try await http.data(for: request, allowNon2xx: true)
        guard (200...299).contains(response.statusCode) else {
            throw PlexError.network(.httpStatus(response.statusCode))
        }

        if let container = try? decoder.decode(APIIdentityContainer.self, from: response.data) {
            return (container.mediaContainer?.machineIdentifier, container.mediaContainer?.version)
        }
        // XML fallback (common default for /identity)
        if let xml = String(data: response.data, encoding: .utf8),
           xml.contains("MediaContainer") {
            let machine = xmlFirstAttribute(xml, name: "machineIdentifier")
            let version = xmlFirstAttribute(xml, name: "version")
            return (machine, version)
        }
        return (nil, nil)
    }

    // MARK: - Internals

    /// Builds a URLRequest without percent-encoding path slashes.
    private func makeRequest(
        base: URL,
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET"
    ) throws -> URLRequest {
        guard let joined = PlexURL.join(base, path: path) else {
            throw PlexError.invalidResponse
        }
        guard var components = URLComponents(url: joined, resolvingAgainstBaseURL: false) else {
            throw PlexError.invalidResponse
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func perform(_ request: URLRequest, allowNon2xx: Bool = false) async throws -> HTTPClient.Response {
        do {
            return try await http.data(for: request, allowNon2xx: allowNon2xx, retryCount: 2)
        } catch let error as HTTPClient.HTTPClientError {
            throw mapHTTPError(error)
        } catch is CancellationError {
            throw PlexError.cancelled
        } catch {
            throw PlexError.network(.transport(error.localizedDescription))
        }
    }

    private func xmlFirstAttribute(_ xml: String, name: String) -> String? {
        // Minimal attribute scrape: name="value"
        guard let range = xml.range(of: "\(name)=\"") else { return nil }
        let start = range.upperBound
        guard let end = xml[start...].firstIndex(of: "\"") else { return nil }
        return String(xml[start..<end])
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.plex.error("Decode failed: \(error.localizedDescription)")
            throw PlexError.decoding(error.localizedDescription)
        }
    }

    private func mapHTTPError(_ error: HTTPClient.HTTPClientError) -> PlexError {
        ErrorMapping.mapHTTP(error)
    }

    private func applyIdentityHeaders(to request: inout URLRequest) {
        for (key, value) in identity.plexHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func applyPMSHeaders(to request: inout URLRequest, token: String) {
        applyIdentityHeaders(to: &request)
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
    }
}
