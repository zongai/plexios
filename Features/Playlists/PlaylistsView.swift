import SwiftUI

/// Playlist list + detail. Parent must provide NavigationStack.
struct PlaylistsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var items: [PlexMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle(L10n.playlists)
            .navigationDestination(for: PlaylistRoute.self) { route in
                PlaylistDetailView(ratingKey: route.ratingKey, title: route.title)
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
                title: "No playlists",
                systemImage: "music.note.list",
                subtitle: "Create playlists on your Plex server to see them here."
            )
        } else {
            List(items) { item in
                NavigationLink(value: PlaylistRoute(ratingKey: item.ratingKey, title: item.title)) {
                    Label(item.title, systemImage: "music.note.list")
                        .foregroundStyle(AppColors.primaryText)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func load(force: Bool = false) async {
        guard let context = environment.serverContext else {
            errorMessage = L10n.noServer
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await environment.playlistsRepository.playlists(context: context, force: force)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlaylistRoute: Hashable {
    let ratingKey: String
    let title: String
}

struct PlaylistDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String
    let title: String
    @State private var items: [PlexMetadata] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if items.isEmpty {
                EmptyStateView(title: "Empty playlist", systemImage: "tray")
            } else {
                List(items) { item in
                    NavigationLink(value: MediaRoute.from(item)) {
                        Text(item.title)
                    }
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
                items = try await environment.playlistsRepository.items(
                    ratingKey: ratingKey,
                    context: context
                )
            } catch { /* soft */ }
            isLoading = false
        }
    }
}
