import Foundation

/// Platform-agnostic surface of the Plex API used by domain services.
/// Concrete HTTP implementation lives in `PlexAPIClient` (iOS) and will be
/// reimplemented on Android TV / Windows against the same contracts.
///
/// See `docs/multi-platform-contracts.md` for request/response semantics.
protocol PlexAPIProtocol: Sendable {
    // MARK: Auth (plex.tv)
    func createPIN() async throws -> PlexPin
    func checkPIN(id: Int, code: String) async throws -> PlexPin

    // MARK: Discovery
    func fetchServers(authToken: String) async throws -> [PlexServer]

    // MARK: Library & Home
    func fetchLibrarySections(baseURL: URL, token: String) async throws -> [PlexLibrary]
    func fetchHomeHubs(baseURL: URL, token: String) async throws -> [PlexHub]
    func fetchLibraryAll(
        sectionKey: String,
        baseURL: URL,
        token: String,
        start: Int,
        size: Int
    ) async throws -> [PlexMetadata]

    // MARK: Metadata
    func fetchMetadata(ratingKey: String, baseURL: URL, token: String) async throws -> PlexMetadata
    func fetchChildren(ratingKey: String, baseURL: URL, token: String) async throws -> [PlexMetadata]
    func fetchRelated(ratingKey: String, baseURL: URL, token: String) async throws -> [PlexHub]
    func fetchContinue(ratingKey: String, baseURL: URL, token: String) async throws -> PlexMetadata?

    // MARK: Collections & Playlists
    func fetchCollections(baseURL: URL, token: String) async throws -> [PlexMetadata]
    func fetchSectionCollections(sectionKey: String, baseURL: URL, token: String) async throws -> [PlexMetadata]
    func fetchCollectionChildren(ratingKey: String, baseURL: URL, token: String) async throws -> [PlexMetadata]
    func fetchPlaylists(baseURL: URL, token: String) async throws -> [PlexMetadata]
    func fetchPlaylistItems(ratingKey: String, baseURL: URL, token: String) async throws -> [PlexMetadata]

    // MARK: Search & Actions
    func search(query: String, baseURL: URL, token: String) async throws -> [PlexHub]
    func rate(key: String, rating: Int, baseURL: URL, token: String) async throws

    // MARK: Identity probe
    func probeIdentity(baseURL: URL, token: String?) async throws -> (machineIdentifier: String?, version: String?)
}
