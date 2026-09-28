import SwiftUI

/// Collections list + detail. Expects an ambient NavigationStack from the parent
/// (More tab / iPad detail wrapper) — does not create a nested stack.
struct CollectionsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var items: [PlexMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle("Collections")
            .navigationDestination(for: CollectionRoute.self) { route in
                CollectionDetailView(ratingKey: route.ratingKey, title: route.title)
            }
            .navigationDestination(for: MediaRoute.self) { MediaDestinationView(route: $0) }
            .refreshable { await load(force: true) }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            LoadingStateView()
        } else if let errorMessage, items.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load(force: true) } }
        } else if items.isEmpty {
            EmptyStateView(
                title: "No collections",
                systemImage: "square.stack",
                subtitle: "Collections from your libraries will appear here."
            )
        } else {
            List(items) { item in
                NavigationLink(value: CollectionRoute(ratingKey: item.ratingKey, title: item.title)) {
                    HStack(spacing: AppSpacing.md) {
                        PlexImage(
                            url: PlexImageURL.resolve(
                                path: item.thumb,
                                baseURL: environment.serverContext?.baseURL,
                                token: environment.serverContext?.token,
                                width: 120,
                                height: 120
                            ),
                            pointSize: CGSize(width: 48, height: 48)
                        )
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(item.title)
                            .foregroundStyle(AppColors.primaryText)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func load(force: Bool = false) async {
        guard let context = environment.serverContext else {
            errorMessage = "No server connected"
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await environment.collectionsRepository.collections(context: context, force: force)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CollectionRoute: Hashable {
    let ratingKey: String
    let title: String
}

struct CollectionDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String
    let title: String
    @State private var children: [PlexMetadata] = []
    @State private var isLoading = true

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: AppLayout.gridSpacing)]
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if children.isEmpty {
                EmptyStateView(title: "Empty collection", systemImage: "tray")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppLayout.gridSpacing) {
                        ForEach(children) { item in
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
                        }
                    }
                    .padding(AppSpacing.lg)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let context = environment.serverContext else {
                isLoading = false
                return
            }
            do {
                children = try await environment.collectionsRepository.children(
                    ratingKey: ratingKey,
                    context: context
                )
            } catch {
                // soft-fail; empty state
            }
            isLoading = false
        }
    }
}
