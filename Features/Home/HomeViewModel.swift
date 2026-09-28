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
            state = .failed("No server connected")
            return
        }

        if case .loaded = state, !force { return }

        state = .loading
        do {
            let result = try await PerformanceSignpost.measure("home.load", logger: logger) {
                try await hubRepository.homeHubs(context: context, force: force)
            }
            hubs = result.filter { !$0.items.isEmpty }
            state = hubs.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as PlexError {
            logger.plex.error("Home load failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
