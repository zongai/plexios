import SwiftUI

// MARK: - Colors (Infuse-inspired cinema palette)

enum AppColors {
    /// Near-black stage used by Infuse-style shelves and detail.
    static let background = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let secondaryBackground = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let tertiaryBackground = Color(red: 0.16, green: 0.16, blue: 0.18)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.72)
    static let tertiaryText = Color.white.opacity(0.48)

    /// Infuse-like cool blue accent.
    static let accent = Color(red: 0.28, green: 0.56, blue: 0.98)
    static let destructive = Color(red: 0.95, green: 0.35, blue: 0.35)

    static let mediaCardBackground = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let posterPlaceholder = Color(red: 0.18, green: 0.18, blue: 0.20)

    static let chipBackground = Color.white.opacity(0.12)
    static let progressTrack = Color.white.opacity(0.22)
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
        case .home: return "Home"
        case .libraries: return "Libraries"
        case .collections: return "Collections"
        case .playlists: return "Playlists"
        case .search: return "Search"
        case .settings: return "Settings"
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
