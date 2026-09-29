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

    init(hubRepository: HubRepository, logger: LogRouter) {
        self.hubRepository = hubRepository
        self.logger = logger
    }

    func load(context: ServerContext?, force: Bool = false) async {
        guard let context else {
            // Bootstrap still connecting — keep loading, do not flash an error.
            if case .loaded = state, !hubs.isEmpty { return }
            state = .loading
            return
        }

        if case .loaded = state, !force { return }

        state = .loading
        do {
            let result = try await PerformanceSignpost.measure("home.load", logger: logger) {
                try await hubRepository.homeHubs(context: context, force: force)
            }
            let prefs = HomeSettingsStore.shared.preferences
            hubs = prefs.filtered(result.filter { !$0.items.isEmpty })
            state = hubs.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as PlexError {
            // Transient connection issues during first connect: stay loading if we have nothing yet
            if hubs.isEmpty, isTransient(error) {
                logger.plex.info("Home load transient: \(error.localizedDescription)")
                state = .loading
                return
            }
            logger.plex.error("Home load failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
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
