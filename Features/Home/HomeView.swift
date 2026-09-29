import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: HomeViewModel?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(environment.connectionManager.activeServer?.name ?? "Home")
                .navigationDestination(for: MediaRoute.self) { route in
                    MediaDestinationView(route: route)
                }
                .refreshable {
                    await viewModel?.load(context: environment.serverContext, force: true)
                }
        }
        .task {
            if viewModel == nil {
                viewModel = HomeViewModel(
                    hubRepository: environment.hubRepository,
                    logger: environment.logger
                )
            }
            await viewModel?.load(context: environment.serverContext)
        }
        // Reload when server identity **or** preferred connection URL changes (LAN vs relay).
        .onChange(of: environment.connectionManager.activeServer?.machineIdentifier) { _, _ in
            Task { await viewModel?.load(context: environment.serverContext, force: true) }
        }
        .onChange(of: environment.serverContext?.baseURL?.absoluteString) { _, newURL in
            guard newURL != nil else { return }
            Task { await viewModel?.load(context: environment.serverContext, force: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state ?? .idle {
        case .idle, .loading:
            if hubsEmpty {
                skeleton
            } else {
                hubList
            }
        case .loaded:
            hubList
        case .empty:
            EmptyStateView(
                title: "Nothing here yet",
                systemImage: "film",
                subtitle: "Play something on your Plex server to populate Home."
            )
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel?.load(context: environment.serverContext, force: true) }
            }
        }
    }

    private var hubsEmpty: Bool { viewModel?.hubs.isEmpty ?? true }

    private var hubList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.xl) {
                ForEach(viewModel?.hubs ?? []) { hub in
                    HubRailView(
                        hub: hub,
                        baseURL: environment.serverContext?.baseURL,
                        token: environment.serverContext?.token
                    ) { item in
                        path.append(MediaRoute.from(item))
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background)
    }

    private var skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        SkeletonBlock(width: 120, height: 20)
                            .padding(.horizontal, AppSpacing.lg)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppLayout.railSpacing) {
                                ForEach(0..<5, id: \.self) { _ in
                                    SkeletonBlock(width: 120, height: 180)
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
    }
}
