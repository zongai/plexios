import SwiftUI

// MARK: - Colors

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
}

// MARK: - Typography

enum AppTypography {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let caption = Font.caption
    static let caption2 = Font.caption2
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
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Layout helpers

enum AppLayout {
    static let posterAspect: CGFloat = 2.0 / 3.0
    static let backdropAspect: CGFloat = 16.0 / 9.0
    static let gridSpacing: CGFloat = AppSpacing.md
    static let railSpacing: CGFloat = AppSpacing.sm

    static func posterWidth(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch horizontalSizeClass {
        case .regular: return 140
        default: return 120
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
