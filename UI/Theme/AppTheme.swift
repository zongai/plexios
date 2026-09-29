import SwiftUI

// MARK: - Colors (system light / dark adaptive)

enum AppColors {
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let tertiaryBackground = Color(.tertiarySystemBackground)

    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)

    static let accent = Color.accentColor
    static let destructive = Color.red

    static let mediaCardBackground = Color(.secondarySystemBackground)
    static let posterPlaceholder = Color(.tertiarySystemFill)

    static let chipBackground = Color(.tertiarySystemFill)
    static let progressTrack = Color(.tertiarySystemFill)

    /// Overlay text on hero artwork (always light for contrast on backdrops).
    static let onMediaPrimary = Color.white
    static let onMediaSecondary = Color.white.opacity(0.85)
}

// MARK: - Typography

enum AppTypography {
    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let title3 = Font.system(.title3, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .default)
    static let subheadline = Font.system(.subheadline, design: .default)
    static let caption = Font.system(.caption, design: .default)
    static let caption2 = Font.system(.caption2, design: .default)
    static let section = Font.system(.title3, design: .rounded).weight(.semibold)
}

// MARK: - Spacing

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum AppCornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
}

// MARK: - Layout helpers

enum AppLayout {
    static let posterAspect: CGFloat = 2.0 / 3.0
    static let backdropAspect: CGFloat = 16.0 / 9.0
    static let gridSpacing: CGFloat = AppSpacing.md
    static let railSpacing: CGFloat = 12

    static func posterWidth(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular: return 150
        default: return 128
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
        case .regular: return 150
        default: return 118
        }
    }

    static let readableContentWidth: CGFloat = 720
}

// MARK: - App sections

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case libraries
    case collections
    case playlists
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return L10n.home
        case .libraries: return L10n.libraries
        case .collections: return L10n.collections
        case .playlists: return L10n.playlists
        case .search: return L10n.search
        case .settings: return L10n.settings
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .libraries: return "books.vertical.fill"
        case .collections: return "square.stack.fill"
        case .playlists: return "music.note.list"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}
