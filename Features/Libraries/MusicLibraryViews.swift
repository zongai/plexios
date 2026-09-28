import SwiftUI

/// Artist → Album → Track hierarchy for music libraries.
struct MusicLibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    let library: PlexLibrary
    @State private var artists: [PlexMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { Task { await load() } }
            } else if artists.isEmpty {
                EmptyStateView(title: "No artists", systemImage: "music.mic")
            } else {
                List(artists) { artist in
                    NavigationLink(value: MusicRoute.artist(ratingKey: artist.ratingKey, title: artist.title)) {
                        Text(artist.title)
                    }
                }
            }
        }
        .navigationTitle(library.title)
        .navigationDestination(for: MusicRoute.self) { route in
            switch route {
            case .artist(let key, let title):
                ArtistAlbumsView(ratingKey: key, title: title)
            case .album(let key, let title):
                AlbumTracksView(ratingKey: key, title: title)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let context = environment.serverContext else {
            errorMessage = "No server connected"
            return
        }
        do {
            artists = try await environment.libraryRepository.items(
                sectionKey: library.key,
                context: context,
                start: 0,
                size: 200
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum MusicRoute: Hashable {
    case artist(ratingKey: String, title: String)
    case album(ratingKey: String, title: String)
}

struct ArtistAlbumsView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String
    let title: String
    @State private var albums: [PlexMetadata] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else {
                List(albums) { album in
                    NavigationLink(value: MusicRoute.album(ratingKey: album.ratingKey, title: album.title)) {
                        Text(album.title)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let context = environment.serverContext else { return }
            albums = (try? await environment.metadataRepository.children(
                ratingKey: ratingKey,
                context: context
            )) ?? []
            isLoading = false
        }
    }
}

struct AlbumTracksView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String
    let title: String
    @State private var tracks: [PlexMetadata] = []
    @State private var isLoading = true
    @State private var playItem: PlexMetadata?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else {
                List(tracks) { track in
                    Button {
                        playItem = track
                    } label: {
                        HStack {
                            Text(track.title)
                                .foregroundStyle(AppColors.primaryText)
                            Spacer()
                            Image(systemName: "play.fill")
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .playerSheet(item: $playItem)
        .task {
            guard let context = environment.serverContext else { return }
            tracks = (try? await environment.metadataRepository.children(
                ratingKey: ratingKey,
                context: context
            )) ?? []
            isLoading = false
        }
    }
}
