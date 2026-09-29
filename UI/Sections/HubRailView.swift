import SwiftUI

/// Horizontal media rail — one card style for the entire row.
struct HubRailView: View {
    let hub: PlexHub
    let baseURL: URL?
    let token: String?
    var onSelect: (PlexMetadata) -> Void

    /// Single style for the whole rail (never mix poster + landscape in one row).
    private var useWideCards: Bool {
        let category = HomeDisplayPreferences.category(for: hub)
        if category == .continueWatching || category == .recentlyPlayed {
            return true
        }
        // If most items are episodes, use landscape for all.
        let episodes = hub.items.filter { $0.type == .episode }.count
        return !hub.items.isEmpty && episodes * 2 >= hub.items.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(hub.title)
                .font(AppTypography.section)
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
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func card(for item: PlexMetadata) -> some View {
        if useWideCards {
            EpisodeCard(
                title: item.type == .episode
                    ? (item.grandparentTitle ?? item.title)
                    : item.title,
                subtitle: item.type == .episode
                    ? (item.cardSubtitle().map { "\($0) · \(item.title)" } ?? item.title)
                    : item.cardSubtitle(),
                imagePath: item.type == .episode
                    ? item.episodeThumbPath()
                    : (item.art ?? item.posterPath()),
                progress: item.isInProgress ? item.progressFraction : nil,
                baseURL: baseURL,
                token: token
            )
        } else {
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
