import Foundation
import Observation

@Observable
@MainActor
final class LibrariesViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded, empty, failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var libraries: [PlexLibrary] = []

    private let repository: LibraryRepository
    private let logger: LogRouter

    init(repository: LibraryRepository, logger: LogRouter) {
        self.repository = repository
        self.logger = logger
    }

    func load(context: ServerContext?, force: Bool = false) async {
        guard let context else {
            if case .loaded = state, !libraries.isEmpty { return }
            state = .loading
            return
        }
        if case .loaded = state, !force { return }

        state = .loading
        do {
            libraries = try await repository.libraries(context: context, force: force)
            state = libraries.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as PlexError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

@Observable
@MainActor
final class LibraryGridViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded, empty, failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var items: [PlexMetadata] = []
    private var nextStart = 0
    private let pageSize = 50
    private(set) var canLoadMore = true

    private let repository: LibraryRepository
    private let sectionKey: String

    init(repository: LibraryRepository, sectionKey: String) {
        self.repository = repository
        self.sectionKey = sectionKey
    }

    func load(context: ServerContext?, force: Bool = false) async {
        guard let context else {
            state = .failed("No server connected")
            return
        }
        if force {
            items = []
            nextStart = 0
            canLoadMore = true
        }
        if case .loaded = state, !force, !items.isEmpty { return }

        state = .loading
        do {
            let page = try await repository.items(
                sectionKey: sectionKey,
                context: context,
                start: 0,
                size: pageSize
            )
            items = page
            nextStart = page.count
            canLoadMore = page.count >= pageSize
            state = items.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as PlexError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore(context: ServerContext?) async {
        guard let context, canLoadMore, state != .loading else { return }
        do {
            let page = try await repository.items(
                sectionKey: sectionKey,
                context: context,
                start: nextStart,
                size: pageSize
            )
            items.append(contentsOf: page)
            nextStart += page.count
            canLoadMore = page.count >= pageSize
        } catch {
            // Soft-fail pagination
        }
    }
}
