import SwiftUI

struct LibrariesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: LibrariesViewModel?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(String(localized: "libraries.title"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SearchView()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(L10n.search)
                    }
                }
                .navigationDestination(for: PlexLibrary.self) { library in
                    if library.type == .artist {
                        MusicLibraryView(library: library)
                    } else {
                        LibraryGridView(library: library)
                    }
                }
                .navigationDestination(for: MediaRoute.self) { route in
                    MediaDestinationView(route: route)
                }
                .refreshable {
                    await viewModel?.load(context: environment.serverContext, force: true)
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: LibraryProgressEvents.popToRoot)) { _ in
            path = NavigationPath()
        }
        .task {
            if viewModel == nil {
                viewModel = LibrariesViewModel(
                    repository: environment.libraryRepository,
                    logger: environment.logger
                )
            }
            await viewModel?.load(context: environment.serverContext)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state ?? .idle {
        case .idle, .loading:
            LoadingStateView()
        case .loaded:
            List {
                browseSection
                Section(String(localized: "libraries.title")) {
                    ForEach(viewModel?.libraries ?? []) { library in
                        NavigationLink(value: library) {
                            LibraryRow(library: library)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        case .empty:
            List {
                browseSection
                Section {
                    EmptyStateView(title: String(localized: "libraries.empty"), systemImage: "books.vertical")
                }
            }
            .listStyle(.insetGrouped)
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel?.load(context: environment.serverContext, force: true) }
            }
        }
    }

    /// Search + Collections + Playlists (formerly the separate “More” tab).
    private var browseSection: some View {
        Section {
            NavigationLink {
                SearchView()
            } label: {
                Label(L10n.search, systemImage: "magnifyingglass")
            }
            NavigationLink {
                CollectionsView()
            } label: {
                Label(L10n.collections, systemImage: "square.stack.fill")
            }
            NavigationLink {
                PlaylistsView()
            } label: {
                Label(L10n.playlists, systemImage: "music.note.list")
            }
        }
    }
}

struct LibraryRow: View {
    let library: PlexLibrary

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(AppColors.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(library.title)
                    .font(AppTypography.headline)
                if let count = library.count {
                    Text(String(format: String(localized: "common.items_count"), count))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var iconName: String {
        switch library.type {
        case .movie: return "film"
        case .show: return "tv"
        case .artist: return "music.note"
        case .photo: return "photo"
        default: return "folder"
        }
    }
}

struct LibraryGridView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.horizontalSizeClass) private var sizeClass
    let library: PlexLibrary
    @State private var viewModel: LibraryGridViewModel?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: AppLayout.gridMinWidth(for: sizeClass)), spacing: AppLayout.gridSpacing)]
    }

    var body: some View {
        content
            .navigationTitle(library.title)
            .navigationBarTitleDisplayMode(.inline)
            // MediaRoute destination is registered on parent LibrariesView NavigationStack
            .task {
                if viewModel == nil {
                    viewModel = LibraryGridViewModel(
                        repository: environment.libraryRepository,
                        sectionKey: library.key
                    )
                }
                await viewModel?.load(context: environment.serverContext)
            }
            .refreshable {
                await viewModel?.load(context: environment.serverContext, force: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state ?? .idle {
        case .idle, .loading:
            LoadingStateView()
        case .loaded:
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppLayout.gridSpacing) {
                    ForEach(viewModel?.items ?? []) { item in
                        NavigationLink(value: MediaRoute.from(item)) {
                            PosterCard(
                                title: item.title,
                                subtitle: item.cardSubtitle(),
                                imagePath: item.posterPath(),
                                progress: item.isInProgress ? item.progressFraction : nil,
                                baseURL: environment.serverContext?.baseURL,
                                token: environment.serverContext?.token
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if item.ratingKey == viewModel?.items.last?.ratingKey {
                                Task { await viewModel?.loadMore(context: environment.serverContext) }
                            }
                        }
                    }
                }
                .padding(AppSpacing.lg)
                .task(id: viewModel?.items.count) {
                    ImagePrefetch.posters(
                        for: viewModel?.items ?? [],
                        baseURL: environment.serverContext?.baseURL,
                        token: environment.serverContext?.token
                    )
                }
            }
        case .empty:
            EmptyStateView(title: String(localized: "libraries.empty_library"), systemImage: "tray")
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel?.load(context: environment.serverContext, force: true) }
            }
        }
    }
}


