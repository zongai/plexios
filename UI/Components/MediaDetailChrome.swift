import SwiftUI

/// Adaptive hero for movie / show / episode detail — portrait vs landscape.
struct MediaDetailHero: View {
    let title: String
    let artPath: String?
    let thumbPath: String?
    let baseURL: URL?
    let token: String?
    var year: Int?
    var contentRating: String?
    var durationLabel: String?
    var rating: Double?
    var isInProgress: Bool = false
    var progress: Double?
    var onPlay: (() -> Void)?
    var secondaryActions: (() -> AnyView)? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Compact when phone is landscape (short height).
    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    private var heroHeight: CGFloat {
        if isCompactHeight { return 160 }
        return sizeClass == .regular ? 320 : 240
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .bottomLeading) {
                PlexImage(
                    url: PlexImageURL.resolve(
                        path: artPath ?? thumbPath,
                        baseURL: baseURL,
                        token: token,
                        width: 1600,
                        height: 900
                    ),
                    pointSize: CGSize(width: min(width, 600), height: heroHeight)
                )
                .frame(width: width, height: heroHeight)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.45),
                            Color.black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(heroHeight * 0.75, 180))
                }

                contentBlock(maxWidth: width - AppSpacing.lg * 2)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, isCompactHeight ? AppSpacing.sm : AppSpacing.md)
            }
            .frame(width: width, height: heroHeight)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func contentBlock(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 4 : AppSpacing.sm) {
            Text(title)
                .font(isCompactHeight ? AppTypography.title3 : AppTypography.largeTitle)
                .foregroundStyle(AppColors.onMediaPrimary)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .lineLimit(isCompactHeight ? 1 : 2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if !isCompactHeight {
                metaChips
                    .frame(maxWidth: maxWidth, alignment: .leading)
            }

            if let progress, progress > 0, progress < 1, !isCompactHeight {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule()
                            .fill(AppColors.accent)
                            .frame(width: max(6, geo.size.width * progress))
                    }
                }
                .frame(height: 4)
                .frame(maxWidth: min(maxWidth, 280))
            }

            HStack(spacing: AppSpacing.sm) {
                if let onPlay {
                    Button(action: onPlay) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text(isInProgress ? L10n.resume : L10n.play)
                                .fontWeight(.semibold)
                        }
                        .font(isCompactHeight ? AppTypography.subheadline : AppTypography.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, isCompactHeight ? 16 : 24)
                        .padding(.vertical, isCompactHeight ? 8 : 12)
                        .background(AppColors.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isInProgress ? L10n.resume : L10n.play)
                }

                if let secondaryActions {
                    secondaryActions()
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: maxWidth)
        }
    }

    private var metaChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chipViews
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipViews
                }
            }
        }
    }

    @ViewBuilder
    private var chipViews: some View {
        if let year {
            chip(String(year))
        }
        if let contentRating {
            chip(contentRating)
        }
        if let durationLabel {
            chip(durationLabel)
        }
        if let rating {
            chip(String(format: "★ %.1f", rating))
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.caption.weight(.medium))
            .foregroundStyle(AppColors.onMediaSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.18), in: Capsule())
            .lineLimit(1)
    }
}

struct MediaDetailIconButton: View {
    let systemImage: String
    let label: String
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isOn ? AppColors.accent : AppColors.onMediaPrimary)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
