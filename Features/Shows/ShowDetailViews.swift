import SwiftUI

// MARK: - Show

struct ShowDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String

    @State private var show: PlexMetadata?
    @State private var seasons: [PlexMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let show {
                content(show)
            } else {
                ErrorStateView(message: errorMessage ?? "Not found") {
                    Task { await load() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ show: PlexMetadata) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        PlexImage(
                            url: PlexImageURL.resolve(
                                path: show.thumb,
                                baseURL: environment.serverContext?.baseURL,
                                token: environment.serverContext?.token,
                                width: 240,
                                height: 360
                            ),
                            pointSize: CGSize(width: 100, height: 150)
                        )
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))

                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(show.title)
                                .font(AppTypography.title)
                            if let year = show.year {
                                Text(String(year))
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            if let leaf = show.leafCount {
                                Text("\(leaf) episodes")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                    }

                    if let summary = show.summary {
                        Text(summary)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            Section("Seasons") {
                ForEach(seasons) { season in
                    NavigationLink(value: MediaRoute.season(
                        ratingKey: season.ratingKey,
                        showTitle: show.title
                    )) {
                        HStack {
                            Text(season.title)
                            Spacer()
                            if let leaf = season.leafCount {
                                Text("\(leaf)")
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        // MediaRoute destinations are registered on the parent NavigationStack
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let context = environment.serverContext else {
            errorMessage = "No server connected"
            return
        }
        do {
            show = try await environment.metadataRepository.metadata(
                ratingKey: ratingKey,
                context: context
            )
            seasons = try await environment.metadataRepository.children(
                ratingKey: ratingKey,
                context: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Season

struct SeasonDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String
    let showTitle: String?

    @State private var episodes: [PlexMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if episodes.isEmpty {
                EmptyStateView(title: "No episodes", systemImage: "tv")
            } else {
                List(episodes) { ep in
                    NavigationLink(value: MediaRoute.episode(ratingKey: ep.ratingKey)) {
                        EpisodeRow(
                            episode: ep,
                            baseURL: environment.serverContext?.baseURL,
                            token: environment.serverContext?.token
                        )
                    }
                }
                // MediaRoute destinations come from parent NavigationStack
            }
        }
        .navigationTitle(showTitle ?? "Season")
        .navigationBarTitleDisplayMode(.inline)
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
            episodes = try await environment.metadataRepository.children(
                ratingKey: ratingKey,
                context: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EpisodeRow: View {
    let episode: PlexMetadata
    let baseURL: URL?
    let token: String?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            PlexImage(
                url: PlexImageURL.resolve(
                    path: episode.thumb,
                    baseURL: baseURL,
                    token: token,
                    width: 320,
                    height: 180
                ),
                pointSize: CGSize(width: 120, height: 68)
            )
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))

            VStack(alignment: .leading, spacing: 4) {
                Text(episodeLabel)
                    .font(AppTypography.headline)
                    .lineLimit(2)
                if episode.isInProgress {
                    ProgressView(value: episode.progressFraction)
                        .tint(AppColors.accent)
                } else if episode.isWatched {
                    Text("Watched")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.tertiaryText)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var episodeLabel: String {
        if let idx = episode.index {
            return "E\(idx) · \(episode.title)"
        }
        return episode.title
    }
}

// MARK: - Episode detail

struct EpisodeDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String

    @State private var item: PlexMetadata?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var playItem: PlexMetadata?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        PlexImage(
                            url: PlexImageURL.resolve(
                                path: item.thumb ?? item.art,
                                baseURL: environment.serverContext?.baseURL,
                                token: environment.serverContext?.token,
                                width: 1280,
                                height: 720
                            ),
                            pointSize: CGSize(width: 400, height: 225)
                        )
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            if let show = item.grandparentTitle {
                                Text(show)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            Text(item.title)
                                .font(AppTypography.title)

                            Button {
                                playItem = item
                            } label: {
                                Label(
                                    item.isInProgress ? "Resume" : "Play",
                                    systemImage: "play.fill"
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.sm)
                            }
                            .buttonStyle(.borderedProminent)

                            if let summary = item.summary {
                                Text(summary)
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        .padding(AppSpacing.lg)
                    }
                }
            } else {
                ErrorStateView(message: errorMessage ?? "Not found") {
                    Task { await load() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .playerSheet(item: $playItem)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let context = environment.serverContext else {
            errorMessage = "No server connected"
            return
        }
        do {
            item = try await environment.metadataRepository.metadata(
                ratingKey: ratingKey,
                context: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
