import SwiftUI

// MARK: - Poster Card (Infuse-style)

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
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                PlexImage(
                    url: PlexImageURL.resolve(
                        path: imagePath,
                        baseURL: baseURL,
                        token: token,
                        width: Int(cardWidth * 2.5),
                        height: Int(cardHeight * 2.5)
                    ),
                    pointSize: CGSize(width: cardWidth, height: cardHeight)
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)

                if let progress, progress > 0, progress < 1 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppColors.progressTrack)
                                Capsule()
                                    .fill(AppColors.accent)
                                    .frame(width: max(4, geo.size.width * progress))
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                    }
                    .frame(width: cardWidth, height: cardHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }

            Text(title)
                .font(AppTypography.caption.weight(.medium))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.tertiaryText)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .mediaAccessibility(title: title, subtitle: subtitle, progress: progress)
    }
}

// MARK: - Episode / Continue Watching card (wide landscape)

struct EpisodeCard: View {
    let title: String
    let subtitle: String?
    let imagePath: String?
    let progress: Double?
    let baseURL: URL?
    let token: String?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardWidth: CGFloat { AppLayout.continueWatchingWidth(for: sizeClass) }
    private var cardHeight: CGFloat { cardWidth / AppLayout.backdropAspect }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                PlexImage(
                    url: PlexImageURL.resolve(
                        path: imagePath,
                        baseURL: baseURL,
                        token: token,
                        width: Int(cardWidth * 2.5),
                        height: Int(cardHeight * 2.5)
                    ),
                    pointSize: CGSize(width: cardWidth, height: cardHeight)
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(title)
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    if let progress, progress > 0, progress < 1 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppColors.progressTrack)
                                Capsule()
                                    .fill(AppColors.accent)
                                    .frame(width: max(4, geo.size.width * progress))
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 2)
                    }
                }
                .padding(10)
                .frame(width: cardWidth, height: cardHeight, alignment: .bottomLeading)
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
