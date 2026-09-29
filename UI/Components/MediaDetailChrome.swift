import SwiftUI

/// Shared Infuse-style hero + action chrome for movie / show detail.
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PlexImage(
                url: PlexImageURL.resolve(
                    path: artPath ?? thumbPath,
                    baseURL: baseURL,
                    token: token,
                    width: 1600,
                    height: 900
                ),
                pointSize: CGSize(width: 420, height: 240)
            )
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    AppColors.background.opacity(0.55),
                    AppColors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)

                metaChips

                if let progress, progress > 0, progress < 1 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColors.progressTrack)
                            Capsule()
                                .fill(AppColors.accent)
                                .frame(width: max(6, geo.size.width * progress))
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 2)
                }

                HStack(spacing: AppSpacing.md) {
                    if let onPlay {
                        Button(action: onPlay) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text(isInProgress ? "Resume" : "Play")
                                    .fontWeight(.semibold)
                            }
                            .font(AppTypography.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(AppColors.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isInProgress ? "Resume" : "Play")
                    }

                    if let secondaryActions {
                        secondaryActions()
                    }
                }
                .padding(.top, AppSpacing.xs)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private var metaChips: some View {
        HStack(spacing: 8) {
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
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.caption.weight(.medium))
            .foregroundStyle(AppColors.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppColors.chipBackground, in: Capsule())
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
                .foregroundStyle(isOn ? AppColors.accent : .white)
                .frame(width: 44, height: 44)
                .background(AppColors.chipBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
