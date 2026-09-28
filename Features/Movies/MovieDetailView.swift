import SwiftUI

struct MovieDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String

    @State private var item: PlexMetadata?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var playItem: PlexMetadata?
    @State private var isFavorite = false

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let item {
                detailScroll(item)
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

    private func detailScroll(_ item: PlexMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    PlexImage(
                        url: PlexImageURL.resolve(
                            path: item.art ?? item.thumb,
                            baseURL: environment.serverContext?.baseURL,
                            token: environment.serverContext?.token,
                            width: 1280,
                            height: 720
                        ),
                        pointSize: CGSize(width: 400, height: 225)
                    )
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, AppColors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                }

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(item.title)
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    metaRow(item)

                    Button {
                        playItem = item
                    } label: {
                        Label(
                            item.isInProgress ? "Resume" : "Play",
                            systemImage: "play.fill"
                        )
                        .font(AppTypography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint(item.isInProgress ? "Resumes from last position" : "Starts playback")

                    HStack(spacing: AppSpacing.md) {
                        Button {
                            Task {
                                guard let context = environment.serverContext else { return }
                                await environment.playbackEngine.setWatched(true, item: item, context: context)
                                await load()
                            }
                        } label: {
                            Label("Watched", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task {
                                guard let context = environment.serverContext else { return }
                                await environment.playbackEngine.setWatched(false, item: item, context: context)
                                await load()
                            }
                        } label: {
                            Label("Unwatched", systemImage: "circle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task {
                                guard let context = environment.serverContext else { return }
                                let next = !isFavorite
                                try? await environment.favoritesRepository.setFavorite(
                                    next,
                                    key: item.key,
                                    context: context
                                )
                                await environment.metadataRepository.invalidate(
                                    ratingKey: item.ratingKey,
                                    machineIdentifier: context.machineIdentifier
                                )
                                isFavorite = next
                            }
                        } label: {
                            Label(
                                isFavorite ? "Favorited" : "Favorite",
                                systemImage: isFavorite ? "star.fill" : "star"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    if let studio = item.studio, !studio.isEmpty {
                        Text(studio)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.tertiaryText)
                    }

                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                    }

                    if !item.genres.isEmpty {
                        taggedSection(title: "Genres", tags: item.genres)
                    }
                    if !item.directors.isEmpty {
                        taggedSection(title: "Director", tags: item.directors)
                    }
                    if !item.writers.isEmpty {
                        taggedSection(title: "Writers", tags: item.writers)
                    }
                    if !item.actors.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Cast")
                                .font(AppTypography.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppSpacing.md) {
                                    ForEach(item.actors, id: \.tag) { role in
                                        VStack {
                                            Text(role.tag)
                                                .font(AppTypography.caption)
                                                .lineLimit(1)
                                            if let r = role.role {
                                                Text(r)
                                                    .font(AppTypography.caption2)
                                                    .foregroundStyle(AppColors.tertiaryText)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .frame(width: 80)
                                    }
                                }
                            }
                        }
                    }

                    if let media = item.media.first {
                        mediaInfo(media)
                    }
                }
                .padding(AppSpacing.lg)
                .readableWidth()
            }
        }
        .background(AppColors.background)
    }

    private func metaRow(_ item: PlexMetadata) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if let year = item.year {
                Text(String(year))
            }
            if let rating = item.contentRating {
                Text("·")
                Text(rating)
            }
            if let duration = item.duration {
                Text("·")
                Text(Self.formatDuration(duration))
            }
            if let r = item.rating {
                Text("·")
                Label(String(format: "%.1f", r), systemImage: "star.fill")
            }
        }
        .font(AppTypography.subheadline)
        .foregroundStyle(AppColors.secondaryText)
    }

    private func taggedSection(title: String, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.headline)
            Text(tags.joined(separator: ", "))
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private func mediaInfo(_ media: PlexMedia) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Media")
                .font(AppTypography.headline)
            let parts = [
                media.videoResolution,
                media.videoCodec?.uppercased(),
                media.audioCodec?.uppercased(),
                media.container?.uppercased()
            ].compactMap { $0 }
            Text(parts.joined(separator: " · "))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let context = environment.serverContext else {
            errorMessage = "No server connected"
            return
        }
        do {
            let loaded = try await environment.metadataRepository.metadata(
                ratingKey: ratingKey,
                context: context
            )
            item = loaded
            isFavorite = loaded.isFavorite
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func formatDuration(_ ms: Int64) -> String {
        let totalSeconds = Int(ms / 1000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
