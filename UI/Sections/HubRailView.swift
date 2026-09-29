import SwiftUI

/// Horizontal media rail — Infuse-style section title + poster shelf.
struct HubRailView: View {
    let hub: PlexHub
    let baseURL: URL?
    let token: String?
    var onSelect: (PlexMetadata) -> Void

    /// Continue Watching / On Deck prefer wide episode cards.
    private var prefersWideCards: Bool {
        let t = hub.title.lowercased()
        return t.contains("continue") || t.contains("on deck") || t.contains("recently")
            || hub.items.first?.type == .episode
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
        if prefersWideCards || item.type == .episode {
            EpisodeCard(
                title: item.type == .episode
                    ? (item.grandparentTitle ?? item.title)
                    : item.title,
                subtitle: item.type == .episode
                    ? (item.cardSubtitle().map { "\($0) · \(item.title)" } ?? item.title)
                    : item.cardSubtitle(),
                imagePath: item.type == .episode ? item.episodeThumbPath() : (item.art ?? item.posterPath()),
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
