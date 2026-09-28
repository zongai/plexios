import SwiftUI

@Observable
@MainActor
final class SearchViewModel {
    var query: String = ""
    private(set) var results: [PlexHub] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    private let repository: SearchRepository
    private var searchTask: Task<Void, Never>?

    init(repository: SearchRepository) {
        self.repository = repository
    }

    func queryChanged(_ newValue: String, context: ServerContext?) {
        query = newValue
        searchTask?.cancel()

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let context else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil

        searchTask = Task {
            // Debounce
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            do {
                let hubs = try await repository.search(query: trimmed, context: context)
                guard !Task.isCancelled else { return }
                results = hubs.filter { !$0.items.isEmpty }
                isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                results = []
                isSearching = false
            }
        }
    }
}

struct SearchView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: SearchViewModel?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Search")
                .navigationDestination(for: MediaRoute.self) { route in
                    MediaDestinationView(route: route)
                }
        }
        .task {
            if viewModel == nil {
                viewModel = SearchViewModel(repository: environment.searchRepository)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let vm = viewModel
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.secondaryText)
                    TextField(
                        "Movies, shows, episodes…",
                        text: Binding(
                            get: { vm?.query ?? "" },
                            set: { vm?.queryChanged($0, context: environment.serverContext) }
                        )
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    if vm?.isSearching == true {
                        ProgressView()
                    }
                }
            }

            if let message = vm?.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(AppColors.destructive)
                        .font(AppTypography.caption)
                }
            }

            if let hubs = vm?.results, !hubs.isEmpty {
                ForEach(hubs) { hub in
                    Section(hub.title) {
                        ForEach(hub.items) { item in
                            Button {
                                path.append(MediaRoute.from(item))
                            } label: {
                                SearchResultRow(
                                    item: item,
                                    baseURL: environment.serverContext?.baseURL,
                                    token: environment.serverContext?.token
                                )
                            }
                        }
                    }
                }
            } else if (vm?.query.count ?? 0) >= 2, vm?.isSearching == false {
                Section {
                    Text("No results")
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct SearchResultRow: View {
    let item: PlexMetadata
    let baseURL: URL?
    let token: String?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            PlexImage(
                url: PlexImageURL.resolve(
                    path: item.posterPath(),
                    baseURL: baseURL,
                    token: token,
                    width: 120,
                    height: 180
                ),
                pointSize: CGSize(width: 40, height: 60)
            )
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)
                Text(typeLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
    }

    private var typeLabel: String {
        switch item.type {
        case .movie: return item.year.map { "Movie · \($0)" } ?? "Movie"
        case .show: return "Show"
        case .episode:
            let show = item.grandparentTitle ?? ""
            return [show, item.cardSubtitle()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        default:
            return item.type.rawValue.capitalized
        }
    }
}
