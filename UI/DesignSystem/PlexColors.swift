import SwiftUI

/// Official Plex client–inspired dark media palette.
/// Default experience is dark; light mode keeps the same media hierarchy with lifted surfaces.
enum PlexColors {
    // MARK: - Surfaces

    /// Near-black stage.
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)   // #121214
            : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    })

    /// Card / list surface.
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)   // #1F1F24
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    })

    /// Elevated chips / bars.
    static let surfaceElevated = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
            : UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1)
    })

    // MARK: - Text

    static let primaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    })

    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.72)
            : UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1)
    })

    static let tertiaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.48)
            : UIColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1)
    })

    /// Classic Plex amber / gold accent.
    static let accent = Color(red: 0.898, green: 0.627, blue: 0.051) // #E5A00D

    static let destructive = Color(red: 0.90, green: 0.30, blue: 0.28)

    static let separator = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.08)
    })

    static let overlay = Color.black.opacity(0.55)
    static let mediaOverlay = Color.black.opacity(0.65)

    static let posterPlaceholder = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1)
    })

    static let progressTrack = Color.white.opacity(0.22)
    static let chipBackground = Color.white.opacity(0.14)

    /// Text drawn on artwork (always light).
    static let onMediaPrimary = Color.white
    static let onMediaSecondary = Color.white.opacity(0.85)
}
