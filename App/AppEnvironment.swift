import Foundation
import Observation

/// Root dependency container. Injected via SwiftUI Environment.
@Observable
@MainActor
final class AppEnvironment {
    // MARK: - Infrastructure

    let logger: LogRouter
    let keychain: KeychainStore
    let httpClient: HTTPClient
    let networkMonitor: NetworkPathMonitor
    let clientIdentity: ClientIdentity

    // MARK: - Plex Core

    let apiClient: PlexAPIClient
    let authenticationService: AuthenticationService
    let connectionManager: ConnectionManager
    let libraryRepository: LibraryRepository
    let hubRepository: HubRepository
    let metadataRepository: MetadataRepository
    let searchRepository: SearchRepository
    let collectionsRepository: CollectionsRepository
    let playlistsRepository: PlaylistsRepository
    let favoritesRepository: FavoritesRepository

    // MARK: - Playback

    let timelineReporter: TimelineReporter
    let playbackEngine: PlaybackEngine

    // MARK: - Init

    init(
        logger: LogRouter = LogRouter(),
        keychain: KeychainStore = KeychainStore(),
        httpClient: HTTPClient? = nil,
        networkMonitor: NetworkPathMonitor = NetworkPathMonitor()
    ) {
        self.logger = logger
        self.keychain = keychain
        self.networkMonitor = networkMonitor

        let identity = ClientIdentity.resolve(keychain: keychain)
        self.clientIdentity = identity

        let http = httpClient ?? HTTPClient(logger: logger)
        self.httpClient = http

        let api = PlexAPIClient(http: http, identity: identity, logger: logger)
        self.apiClient = api

        self.authenticationService = AuthenticationService(
            api: api,
            keychain: keychain,
            logger: logger
        )
        self.connectionManager = ConnectionManager(
            api: api,
            networkMonitor: networkMonitor,
            logger: logger
        )
        self.libraryRepository = LibraryRepository(api: api)
        self.hubRepository = HubRepository(api: api)
        self.metadataRepository = MetadataRepository(api: api)
        self.searchRepository = SearchRepository(api: api)
        self.collectionsRepository = CollectionsRepository(api: api)
        self.playlistsRepository = PlaylistsRepository(api: api)
        self.favoritesRepository = FavoritesRepository(api: api)

        let reporter = TimelineReporter(http: http, logger: logger)
        self.timelineReporter = reporter
        self.playbackEngine = PlaybackEngine(
            timelineReporter: reporter,
            http: http,
            logger: logger,
            clientIdentifier: identity.clientIdentifier,
            identityHeaders: identity.plexHeaders
        )

        self.networkMonitor.start()
        self.logger.app.info("AppEnvironment initialized (gap-fill)")
    }

    func bootstrap() async {
        await authenticationService.restoreSession()

        if case .signedIn = authenticationService.state,
           let token = authenticationService.authToken {
            await connectionManager.discover(authToken: token)
            connectionManager.startObservingNetworkChanges { [weak self] in
                self?.authenticationService.authToken
            }
        }
    }

    var serverContext: ServerContext? {
        guard let server = connectionManager.activeServer,
              let base = server.preferredConnection?.baseURL
        else { return nil }
        return ServerContext(
            baseURL: base,
            token: server.accessToken,
            machineIdentifier: server.machineIdentifier
        )
    }
}
