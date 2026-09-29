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
        guard !trimmed.isEmpty, let context else {
            results = []
            isSearching = false
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
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
            searchContent
                .navigationTitle(L10n.search)
                .navigationDestination(for: MediaRoute.self) { route in
                    MediaDestinationView(route: route)
                }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SearchViewModel(repository: environment.searchRepository)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if let viewModel {
            SearchResultsList(
                viewModel: viewModel,
                path: $path,
                serverContext: environment.serverContext
            )
        } else {
            ProgressView()
        }
    }
}

/// Isolated so `@Bindable` tracks SearchViewModel mutations reliably.
private struct SearchResultsList: View {
    @Bindable var viewModel: SearchViewModel
    @Binding var path: NavigationPath
    let serverContext: ServerContext?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.secondaryText)
                    TextField(
                        L10n.searchPlaceholder,
                        text: Binding(
                            get: { viewModel.query },
                            set: { viewModel.queryChanged($0, context: serverContext) }
                        )
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    if viewModel.isSearching {
                        ProgressView()
                    }
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(AppColors.destructive)
                        .font(AppTypography.caption)
                }
            }

            if !viewModel.results.isEmpty {
                ForEach(viewModel.results) { hub in
                    Section(MediaDisplayFormatting.hubTitle(hub)) {
                        ForEach(hub.items) { item in
                            Button {
                                path.append(MediaRoute.from(item))
                            } label: {
                                SearchResultRow(
                                    item: item,
                                    baseURL: serverContext?.baseURL,
                                    token: serverContext?.token
                                )
                            }
                        }
                    }
                }
            } else if !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !viewModel.isSearching {
                Section {
                    Text(L10n.noResults)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
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
