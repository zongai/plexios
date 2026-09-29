import SwiftUI

// MARK: - Show

struct ShowDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String

    @State private var show: PlexMetadata?
    @State private var seasons: [PlexMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var playItem: PlexMetadata?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let show {
                content(show)
            } else {
                ErrorStateView(message: errorMessage ?? L10n.notFound) {
                    Task { await load() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(AppColors.background.opacity(0.92), for: .navigationBar)
        .task { await load() }
        .playerSheet(item: $playItem)
    }

    private func content(_ show: PlexMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MediaDetailHero(
                    title: show.title,
                    artPath: show.art,
                    thumbPath: show.thumb,
                    baseURL: environment.serverContext?.baseURL,
                    token: environment.serverContext?.token,
                    year: show.year,
                    contentRating: show.contentRating,
                    durationLabel: show.leafCount.map { L10n.episodesCount($0) },
                    rating: show.rating,
                    isInProgress: show.isInProgress,
                    progress: show.isInProgress ? show.progressFraction : nil,
                    onPlay: {
                        Task { await playShow(show) }
                    },
                    secondaryActions: nil
                )

                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    if let summary = show.summary, !summary.isEmpty {
                        Text(summary)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineSpacing(3)
                    }

                    if !seasons.isEmpty {
                        Text(L10n.seasons)
                            .font(AppTypography.section)
                            .foregroundStyle(AppColors.primaryText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: AppLayout.railSpacing) {
                                ForEach(seasons) { season in
                                    NavigationLink(value: MediaRoute.season(
                                        ratingKey: season.ratingKey,
                                        showTitle: show.title
                                    )) {
                                        PosterCard(
                                            title: season.title,
                                            subtitle: season.leafCount.map { L10n.episodesCount($0) },
                                            imagePath: season.thumb ?? show.thumb,
                                            progress: nil,
                                            baseURL: environment.serverContext?.baseURL,
                                            token: environment.serverContext?.token
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let context = environment.serverContext else {
            errorMessage = L10n.noServer
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

    /// Resolve a playable episode (in-progress preferred, else first episode of first season).
    private func playShow(_ show: PlexMetadata) async {
        guard let context = environment.serverContext else { return }
        var fallback: PlexMetadata?
        for season in seasons {
            guard let eps = try? await environment.metadataRepository.children(
                ratingKey: season.ratingKey,
                context: context
            ) else { continue }
            let episodes = eps.filter { $0.type == .episode }
            if let progress = episodes.first(where: { $0.isInProgress }) {
                playItem = progress
                return
            }
            if fallback == nil {
                fallback = episodes.first
            }
        }
        playItem = fallback ?? show
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
                EmptyStateView(title: L10n.noEpisodes, systemImage: "tv")
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.md) {
                        ForEach(episodes) { ep in
                            NavigationLink(value: MediaRoute.episode(ratingKey: ep.ratingKey)) {
                                EpisodeRow(
                                    episode: ep,
                                    baseURL: environment.serverContext?.baseURL,
                                    token: environment.serverContext?.token
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AppSpacing.lg)
                }
                .background(AppColors.background.ignoresSafeArea())
            }
        }
        .navigationTitle(showTitle ?? L10n.season)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let context = environment.serverContext else {
            errorMessage = L10n.noServer
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
            ZStack(alignment: .bottom) {
                PlexImage(
                    url: PlexImageURL.resolve(
                        path: episode.thumb,
                        baseURL: baseURL,
                        token: token,
                        width: 320,
                        height: 180
                    ),
                    pointSize: CGSize(width: 140, height: 80)
                )
                .frame(width: 140, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm, style: .continuous))

                if episode.isInProgress {
                    let p = episode.progressFraction
                    if p > 0, p < 1 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppColors.progressTrack)
                                Capsule().fill(AppColors.accent).frame(width: geo.size.width * p)
                            }
                        }
                        .frame(height: 3)
                        .padding(6)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)
                if let sub = episode.cardSubtitle() {
                    Text(sub)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.tertiaryText)
                }
                if let summary = episode.summary {
                    Text(summary)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))
    }
}
