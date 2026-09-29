import Foundation
import Observation

@Observable
@MainActor
final class SearchViewModel {
    private(set) var query: String = ""
    private(set) var results: [PlexHub] = []
    private(set) var isSearching: Bool = false
    private(set) var errorMessage: String?

    private let repository: SearchRepository
    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init(repository: SearchRepository) {
        self.repository = repository
    }

    func queryChanged(_ newValue: String, context: ServerContext?) {
        query = newValue
        errorMessage = nil

        debounceTask?.cancel()
        searchTask?.cancel()

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        guard let context else {
            results = []
            isSearching = false
            errorMessage = L10n.noServer
            return
        }

        isSearching = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.performSearch(query: trimmed, context: context)
        }
    }

    private func performSearch(query: String, context: ServerContext) async {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let hubs = try await repository.search(query: query, context: context)
                guard !Task.isCancelled else { return }
                // Keep only hubs that still match current query
                if self.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == query.lowercased()
                {
                    results = hubs.filter { !$0.items.isEmpty }
                    isSearching = false
                    errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if self.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == query.lowercased()
                {
                    results = []
                    isSearching = false
                    errorMessage = error.localizedDescription
                }
            }
        }
        await searchTask?.value
    }
}
