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
    /// Single in-flight work unit: debounce sleep + network search (cancellable as one).
    private var workTask: Task<Void, Never>?

    init(repository: SearchRepository) {
        self.repository = repository
    }

    func queryChanged(_ newValue: String, context: ServerContext?) {
        query = newValue
        errorMessage = nil

        workTask?.cancel()
        workTask = nil

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
        workTask = Task { [weak self] in
            // Debounce keystrokes
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }

            do {
                let hubs = try await repository.search(query: trimmed, context: context)
                guard !Task.isCancelled else { return }
                guard self.matchesCurrentQuery(trimmed) else { return }
                results = hubs.filter { !$0.items.isEmpty }
                isSearching = false
                errorMessage = nil
            } catch is CancellationError {
                // Newer keystroke owns UI state
                return
            } catch {
                guard !Task.isCancelled, self.matchesCurrentQuery(trimmed) else { return }
                results = []
                isSearching = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func matchesCurrentQuery(_ searchQuery: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == searchQuery.lowercased()
    }
}
