import SwiftUI

// MARK: - Colors (aliases → Plex Design System)

enum AppColors {
    static let background = PlexColors.background
    static let secondaryBackground = PlexColors.surface
    static let tertiaryBackground = PlexColors.surfaceElevated

    static let primaryText = PlexColors.primaryText
    static let secondaryText = PlexColors.secondaryText
    static let tertiaryText = PlexColors.tertiaryText

    static let accent = PlexColors.accent
    static let destructive = PlexColors.destructive

    static let mediaCardBackground = PlexColors.surface
    static let posterPlaceholder = PlexColors.posterPlaceholder

    static let chipBackground = PlexColors.chipBackground
    static let progressTrack = PlexColors.progressTrack

    static let onMediaPrimary = PlexColors.onMediaPrimary
    static let onMediaSecondary = PlexColors.onMediaSecondary
}

// MARK: - Typography

enum AppTypography {
    static let largeTitle = PlexTypography.largeTitle
    static let title = PlexTypography.heroTitle
    static let title3 = Font.system(.title3, design: .rounded).weight(.semibold)
    static let headline = PlexTypography.button
    static let body = PlexTypography.body
    static let subheadline = PlexTypography.secondary
    static let caption = PlexTypography.caption
    static let caption2 = PlexTypography.metadata
    static let section = PlexTypography.sectionTitle
}

// MARK: - Spacing

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = PlexSpacing.xs
    static let sm: CGFloat = PlexSpacing.sm
    static let md: CGFloat = PlexSpacing.md
    static let lg: CGFloat = PlexSpacing.lg
    static let xl: CGFloat = PlexSpacing.xl
    static let xxl: CGFloat = PlexSpacing.xxl
}

// MARK: - Corner Radius

enum AppCornerRadius {
    static let sm: CGFloat = PlexRadius.sm
    static let md: CGFloat = PlexRadius.card
    static let lg: CGFloat = PlexRadius.lg
    static let xl: CGFloat = PlexRadius.xl
}

// MARK: - Layout helpers

enum AppLayout {
    static let posterAspect: CGFloat = 2.0 / 3.0
    static let backdropAspect: CGFloat = 16.0 / 9.0
    static let gridSpacing: CGFloat = PlexSpacing.md
    static let railSpacing: CGFloat = PlexSpacing.railGap

    static func posterWidth(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular: return 150
        default: return 120
        }
    }

    static func continueWatchingWidth(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular: return 280
        default: return 220
        }
    }

    static func gridMinWidth(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular: return 140
        default: return 110
        }
    }

    static let readableContentWidth: CGFloat = 720
}

// MARK: - App sections

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case libraries
    case iptv
    case settings

    var id: String { rawValue }

    /// Primary tabs / iPad sidebar (search, collections, playlists live under Libraries).
    static var sidebarCases: [AppSection] { allCases }

    var title: String {
        switch self {
        case .home: return L10n.home
        case .libraries: return L10n.libraries
        case .iptv: return String(localized: "iptv.title")
        case .settings: return L10n.settings
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .libraries: return PlexIcon.library
        case .iptv: return "tv"
        case .settings: return PlexIcon.settings
        }
    }
}
