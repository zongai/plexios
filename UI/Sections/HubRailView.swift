import SwiftUI

/// Horizontal media rail for a single hub.
struct HubRailView: View {
    let hub: PlexHub
    let baseURL: URL?
    let token: String?
    var onSelect: (PlexMetadata) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(hub.title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.primaryText)
                .padding(.horizontal, AppSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppLayout.railSpacing) {
                    ForEach(hub.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            card(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
        }
    }

    @ViewBuilder
    private func card(for item: PlexMetadata) -> some View {
        switch item.type {
        case .episode:
            EpisodeCard(
                title: item.title,
                subtitle: item.cardSubtitle() ?? item.grandparentTitle,
                imagePath: item.episodeThumbPath(),
                progress: item.isInProgress ? item.progressFraction : nil,
                baseURL: baseURL,
                token: token
            )
        default:
            PosterCard(
                title: item.title,
                subtitle: item.cardSubtitle(),
                imagePath: item.posterPath(),
                progress: item.isInProgress ? item.progressFraction : nil,
                baseURL: baseURL,
                token: token
            )
        }
    }
}
