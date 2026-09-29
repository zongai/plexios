import SwiftUI

/// Plex media hierarchy — prefers rounded for titles, default for body/metadata.
enum PlexTypography {
    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let heroTitle = Font.system(.title, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)
    static let cardTitle = Font.system(.caption, design: .default).weight(.semibold)
    static let body = Font.system(.body, design: .default)
    static let secondary = Font.system(.subheadline, design: .default)
    static let caption = Font.system(.caption, design: .default)
    static let metadata = Font.system(.caption2, design: .default).weight(.medium)
    static let button = Font.system(.headline, design: .rounded).weight(.semibold)
}
