import SwiftUI

// MARK: - Poster Card

struct PosterCard: View {
    let title: String
    let subtitle: String?
    let imagePath: String?
    let progress: Double?
    let baseURL: URL?
    let token: String?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardWidth: CGFloat { AppLayout.posterWidth(for: sizeClass) }
    private var cardHeight: CGFloat { cardWidth / AppLayout.posterAspect }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ZStack(alignment: .bottomLeading) {
                PlexImage(
                    url: PlexImageURL.resolve(
                        path: imagePath,
                        baseURL: baseURL,
                        token: token,
                        width: Int(cardWidth * 2),
                        height: Int(cardHeight * 2)
                    ),
                    pointSize: CGSize(width: cardWidth, height: cardHeight)
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))

                if let progress, progress > 0, progress < 1 {
                    ProgressView(value: progress)
                        .tint(AppColors.accent)
                        .padding(AppSpacing.xs)
                        .accessibilityHidden(true)
                }
            }

            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .mediaAccessibility(title: title, subtitle: subtitle, progress: progress)
    }
}

// MARK: - Episode Card

struct EpisodeCard: View {
    let title: String
    let subtitle: String?
    let imagePath: String?
    let progress: Double?
    let baseURL: URL?
    let token: String?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardWidth: CGFloat {
        sizeClass == .regular ? 240 : 200
    }
    private var cardHeight: CGFloat { cardWidth / AppLayout.backdropAspect }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ZStack(alignment: .bottom) {
                PlexImage(
                    url: PlexImageURL.resolve(
                        path: imagePath,
                        baseURL: baseURL,
                        token: token,
                        width: Int(cardWidth * 2),
                        height: Int(cardHeight * 2)
                    ),
                    pointSize: CGSize(width: cardWidth, height: cardHeight)
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))

                if let progress, progress > 0, progress < 1 {
                    ProgressView(value: progress)
                        .tint(AppColors.accent)
                        .padding(AppSpacing.xs)
                        .accessibilityHidden(true)
                }
            }

            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .mediaAccessibility(title: title, subtitle: subtitle, progress: progress)
    }
}

// MARK: - Helpers from metadata

extension PlexMetadata {
    func posterPath() -> String? { thumb ?? parentThumb ?? grandparentThumb }
    func episodeThumbPath() -> String? { thumb ?? parentThumb }

    func cardSubtitle() -> String? {
        switch type {
        case .movie:
            return year.map(String.init)
        case .show:
            if let leaf = leafCount { return "\(leaf) episodes" }
            return year.map(String.init)
        case .episode:
            var parts: [String] = []
            if let s = parentIndex { parts.append("S\(s)") }
            if let e = index { parts.append("E\(e)") }
            if parts.isEmpty { return grandparentTitle ?? parentTitle }
            return parts.joined(separator: " · ")
        default:
            return year.map(String.init)
        }
    }
}
