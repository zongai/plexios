import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: HomeViewModel?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(environment.connectionManager.activeServer?.name ?? L10n.home)
                .navigationBarTitleDisplayMode(.large)
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
            await loadHome()
        }
        .onChange(of: environment.connectionManager.activeServer?.machineIdentifier) { _, _ in
            Task { await loadHome(force: true) }
        }
        .onChange(of: environment.serverContext?.baseURL.absoluteString) { _, newURL in
            guard newURL != nil else { return }
            Task { await loadHome(force: true) }
        }
        .onAppear {
            // Re-apply home display preferences when returning from Settings
            Task { await loadHome(force: true) }
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
                title: L10n.homeEmptyTitle,
                systemImage: "film",
                subtitle: L10n.homeEmptySubtitle
            )
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await loadHome(force: true) }
            }
        }
    }

    private var hubsEmpty: Bool { viewModel?.hubs.isEmpty ?? true }

    private func loadHome(force: Bool = false) async {
        var libraries: [PlexLibrary] = []
        if let context = environment.serverContext {
            libraries = (try? await environment.libraryRepository.libraries(context: context)) ?? []
        }
        await viewModel?.load(context: environment.serverContext, libraries: libraries, force: force)
    }

    private var hubList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.xxl) {
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
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    private var skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        SkeletonBlock(width: 140, height: 22)
                            .padding(.horizontal, AppSpacing.lg)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppLayout.railSpacing) {
                                ForEach(0..<5, id: \.self) { _ in
                                    SkeletonBlock(width: 128, height: 192)
                                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md))
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background.ignoresSafeArea())
    }
}
