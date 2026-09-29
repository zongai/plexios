import SwiftUI

/// Horizontal media rail — one card style for the entire row.
struct HubRailView: View {
    let hub: PlexHub
    let baseURL: URL?
    let token: String?
    var onSelect: (PlexMetadata) -> Void

    /// Single style for the whole rail (never mix poster + landscape in one row).
    private var useWideCards: Bool {
        switch HomeDisplayPreferences.personalKind(for: hub) {
        case .continueWatching, .recentlyPlayed:
            return true
        case .recentlyAdded, .none:
            break
        }
        let episodes = hub.items.filter { $0.type == .episode }.count
        return !hub.items.isEmpty && episodes * 2 >= hub.items.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PlexSpacing.md) {
            Text(MediaDisplayFormatting.hubTitle(hub))
                .font(AppTypography.section)
                .foregroundStyle(AppColors.primaryText)
                .padding(.horizontal, PlexSpacing.pageHorizontal)

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
                .padding(.horizontal, PlexSpacing.pageHorizontal)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func card(for item: PlexMetadata) -> some View {
        if useWideCards {
            EpisodeCard(
                title: MediaDisplayFormatting.cardTitle(for: item, wide: true),
                subtitle: MediaDisplayFormatting.cardSubtitle(for: item, wide: true),
                imagePath: item.type == .episode
                    ? item.episodeThumbPath()
                    : (item.art ?? item.posterPath()),
                progress: item.isInProgress ? item.progressFraction : nil,
                baseURL: baseURL,
                token: token
            )
        } else {
            PosterCard(
                title: MediaDisplayFormatting.cardTitle(for: item, wide: false),
                subtitle: MediaDisplayFormatting.cardSubtitle(for: item, wide: false),
                imagePath: item.posterPath(),
                progress: item.isInProgress ? item.progressFraction : nil,
                baseURL: baseURL,
                token: token
            )
        }
    }
}
