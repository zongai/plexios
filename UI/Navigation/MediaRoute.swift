import Foundation

/// Type-safe navigation routes for media detail hierarchy.
enum MediaRoute: Hashable {
    case movie(ratingKey: String)
    case show(ratingKey: String)
    case season(ratingKey: String, showTitle: String?)
    case episode(ratingKey: String)

    static func from(_ item: PlexMetadata) -> MediaRoute {
        switch item.type {
        case .movie:
            return .movie(ratingKey: item.ratingKey)
        case .show:
            return .show(ratingKey: item.ratingKey)
        case .season:
            return .season(ratingKey: item.ratingKey, showTitle: item.parentTitle)
        case .episode:
            return .episode(ratingKey: item.ratingKey)
        default:
            // Fallback: treat as movie-like detail
            return .movie(ratingKey: item.ratingKey)
        }
    }
}
