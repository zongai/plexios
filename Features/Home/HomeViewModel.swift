import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var hubs: [PlexHub] = []

    private let hubRepository: HubRepository
    private let logger: LogRouter

    /// Raw hubs from last successful fetch (before display filtering).
    private var lastRawHubs: [PlexHub] = []
    private var lastLibraries: [PlexLibrary] = []
    /// Bumps on each load so late responses from a previous server are ignored.
    private var loadGeneration: UInt64 = 0
    private var lastMachineId: String?

    init(hubRepository: HubRepository, logger: LogRouter) {
        self.hubRepository = hubRepository
        self.logger = logger
    }

    func load(context: ServerContext?, libraries: [PlexLibrary] = [], force: Bool = false) async {
        guard let context else {
            if case .loaded = state, !hubs.isEmpty { return }
            state = .loading
            return
        }

        let machineChanged = lastMachineId != nil && lastMachineId != context.machineIdentifier
        if case .loaded = state, !force, !machineChanged { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        lastMachineId = context.machineIdentifier
        lastLibraries = libraries

        // Keep showing previous hubs while refreshing (avoid full-screen skeleton flicker)
        if hubs.isEmpty {
            state = .loading
        }

        do {
            let result = try await PerformanceSignpost.measure("home.load", logger: logger) {
                try await hubRepository.homeHubs(context: context, force: force || machineChanged)
            }
            guard generation == loadGeneration else {
                logger.plex.debug("Home load discarded (stale generation)")
                return
            }
            lastRawHubs = result.filter { !$0.items.isEmpty }
            applyDisplayFilter(libraries: libraries)
        } catch is CancellationError {
            return
        } catch let error as PlexError {
            guard generation == loadGeneration else { return }
            if hubs.isEmpty, isTransient(error) {
                logger.plex.info("Home load transient: \(error.localizedDescription)")
                state = .loading
                return
            }
            logger.plex.error("Home load failed: \(error.localizedDescription)")
            if hubs.isEmpty {
                state = .failed(error.localizedDescription)
            }
        } catch {
            guard generation == loadGeneration else { return }
            if hubs.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-run Home display preferences on cached hubs (no network).
    /// Call when returning from Settings so toggles apply immediately.
    func reapplyPreferences(libraries: [PlexLibrary]? = nil) {
        if let libraries {
            lastLibraries = libraries
        }
        guard !lastRawHubs.isEmpty else { return }
        applyDisplayFilter(libraries: lastLibraries)
    }

    private func applyDisplayFilter(libraries: [PlexLibrary]) {
        let prefs = HomeSettingsStore.shared.preferences
        hubs = prefs.filtered(lastRawHubs, libraries: libraries)
        state = hubs.isEmpty ? .empty : .loaded
    }

    private func isTransient(_ error: PlexError) -> Bool {
        switch error {
        case .network(.timeout), .network(.offline), .serverUnavailable, .mediaUnavailable:
            return true
        case .network(.httpStatus(let code)) where (500...599).contains(code):
            return true
        default:
            return false
        }
    }
}
