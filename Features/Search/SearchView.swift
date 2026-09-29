import SwiftUI

/// Search UI that participates in the **parent** NavigationStack (no nested stack).
/// Pushing media uses `NavigationLink(value: MediaRoute)` so Back pops one level correctly.
struct SearchView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: SearchViewModel?

    var body: some View {
        searchContent
            .navigationTitle(L10n.search)
            .navigationBarTitleDisplayMode(.large)
            .task {
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
                serverContext: environment.serverContext
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SearchResultsList: View {
    @Bindable var viewModel: SearchViewModel
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
                            NavigationLink(value: MediaRoute.from(item)) {
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
                    Text(String(localized: "search.no_results"))
                        .foregroundStyle(AppColors.secondaryText)
                        .font(AppTypography.body)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct SearchResultRow: View {
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
                pointSize: CGSize(width: 44, height: 66)
            )
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)
                if let sub = MediaDisplayFormatting.cardSubtitle(for: item, wide: false) {
                    Text(sub)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
