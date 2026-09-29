import SwiftUI

/// Episode detail — same Infuse-style chrome as movies, with show/season context.
struct EpisodeDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let ratingKey: String

    @State private var item: PlexMetadata?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var playItem: PlexMetadata?

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
                    artPath: item.art ?? item.thumb,
                    thumbPath: item.thumb,
                    baseURL: environment.serverContext?.baseURL,
                    token: environment.serverContext?.token,
                    year: item.year,
                    contentRating: item.contentRating,
                    durationLabel: item.duration.map(MovieDetailView.formatDuration),
                    rating: item.rating,
                    isInProgress: item.isInProgress,
                    progress: item.isInProgress ? item.progressFraction : nil,
                    onPlay: { playItem = item },
                    secondaryActions: nil
                )

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if let show = item.grandparentTitle {
                        Text(show)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.primaryText)
                    }
                    if let sub = item.cardSubtitle() {
                        Text(sub)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineSpacing(3)
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
            item = try await environment.metadataRepository.metadata(
                ratingKey: ratingKey,
                context: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
