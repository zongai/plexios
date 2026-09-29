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
                ErrorStateView(message: errorMessage ?? L10n.notFound) {
                    Task { await load() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .playerSheet(item: $playItem)
    }

    private func detailScroll(_ item: PlexMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MediaDetailHero(
                    title: item.title,
                    artPath: item.art,
                    thumbPath: item.thumb,
                    baseURL: environment.serverContext?.baseURL,
                    token: environment.serverContext?.token,
                    year: item.year,
                    contentRating: item.contentRating,
                    durationLabel: item.duration.map(Self.formatDuration),
                    rating: item.rating,
                    isInProgress: item.isInProgress,
                    progress: item.isInProgress ? item.progressFraction : nil,
                    onPlay: { playItem = item },
                    secondaryActions: {
                        AnyView(
                            HStack(spacing: AppSpacing.sm) {
                                MediaDetailIconButton(
                                    systemImage: (item.viewCount ?? 0) > 0 ? "checkmark.circle.fill" : "checkmark.circle",
                                    label: L10n.markWatched,
                                    isOn: (item.viewCount ?? 0) > 0
                                ) {
                                    Task {
                                        guard let context = environment.serverContext else { return }
                                        await environment.playbackEngine.setWatched(true, item: item, context: context)
                                        await load()
                                    }
                                }
                                MediaDetailIconButton(
                                    systemImage: isFavorite ? "star.fill" : "star",
                                    label: isFavorite ? L10n.unfavorite : L10n.favorite,
                                    isOn: isFavorite
                                ) {
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
                                }
                            }
                        )
                    }
                )

                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    if let studio = item.studio, !studio.isEmpty {
                        Text(studio)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.tertiaryText)
                    }

                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineSpacing(3)
                    }

                    if !item.genres.isEmpty {
                        flowTags(title: L10n.genres, tags: item.genres)
                    }
                    if !item.directors.isEmpty {
                        flowTags(title: L10n.director, tags: item.directors)
                    }
                    if !item.writers.isEmpty {
                        flowTags(title: L10n.writers, tags: item.writers)
                    }

                    if !item.actors.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(L10n.cast)
                                .font(AppTypography.headline)
                                .foregroundStyle(AppColors.primaryText)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppSpacing.md) {
                                    ForEach(item.actors, id: \.tag) { role in
                                        VStack(spacing: 6) {
                                            Circle()
                                                .fill(AppColors.tertiaryBackground)
                                                .frame(width: 56, height: 56)
                                                .overlay {
                                                    Text(String(role.tag.prefix(1)))
                                                        .font(AppTypography.headline)
                                                        .foregroundStyle(AppColors.secondaryText)
                                                }
                                            Text(role.tag)
                                                .font(AppTypography.caption2)
                                                .foregroundStyle(AppColors.primaryText)
                                                .lineLimit(1)
                                            if let r = role.role {
                                                Text(r)
                                                    .font(AppTypography.caption2)
                                                    .foregroundStyle(AppColors.tertiaryText)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .frame(width: 72)
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
        .background(AppColors.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    private func flowTags(title: String, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.primaryText)
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(AppTypography.caption.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.chipBackground, in: Capsule())
                }
            }
        }
    }

    private func mediaInfo(_ media: PlexMedia) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(L10n.media)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.primaryText)
            let parts = [
                media.videoResolution,
                media.videoCodec?.uppercased(),
                media.audioCodec?.uppercased(),
                media.container?.uppercased()
            ].compactMap { $0 }
            Text(parts.joined(separator: " · "))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.tertiaryText)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let context = environment.serverContext else {
            errorMessage = L10n.noServer
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

// Simple wrapping layout for genre chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x)
            totalHeight = y + rowHeight
        }
        return (CGSize(width: totalWidth, height: totalHeight), origins)
    }
}
