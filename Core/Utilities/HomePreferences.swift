import Foundation

/// Which home hub categories the user wants on the Home screen.
struct HomeDisplayPreferences: Sendable, Equatable {
    var showContinueWatching: Bool
    var showRecentlyAdded: Bool
    var showRecentlyPlayed: Bool
    var showMovies: Bool
    var showTV: Bool
    var showMusic: Bool
    var showOther: Bool
    /// Max items kept per hub (server may return more).
    var maxItemsPerHub: Int

    static let `default` = HomeDisplayPreferences(
        showContinueWatching: true,
        showRecentlyAdded: true,
        showRecentlyPlayed: true,
        showMovies: true,
        showTV: true,
        showMusic: true,
        showOther: true,
        maxItemsPerHub: 20
    )

    enum Category: String, CaseIterable, Identifiable {
        case continueWatching
        case recentlyAdded
        case recentlyPlayed
        case movies
        case tv
        case music
        case other

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .continueWatching: return "home.pref.continue"
            case .recentlyAdded: return "home.pref.recently_added"
            case .recentlyPlayed: return "home.pref.recently_played"
            case .movies: return "home.pref.movies"
            case .tv: return "home.pref.tv"
            case .music: return "home.pref.music"
            case .other: return "home.pref.other"
            }
        }

        var title: String { String(localized: String.LocalizationValue(titleKey)) }
    }

    func isEnabled(_ category: Category) -> Bool {
        switch category {
        case .continueWatching: return showContinueWatching
        case .recentlyAdded: return showRecentlyAdded
        case .recentlyPlayed: return showRecentlyPlayed
        case .movies: return showMovies
        case .tv: return showTV
        case .music: return showMusic
        case .other: return showOther
        }
    }

    mutating func set(_ category: Category, enabled: Bool) {
        switch category {
        case .continueWatching: showContinueWatching = enabled
        case .recentlyAdded: showRecentlyAdded = enabled
        case .recentlyPlayed: showRecentlyPlayed = enabled
        case .movies: showMovies = enabled
        case .tv: showTV = enabled
        case .music: showMusic = enabled
        case .other: showOther = enabled
        }
    }

    /// Classify a Plex home hub by identifier / title / type.
    static func category(for hub: PlexHub) -> Category {
        let id = (hub.hubIdentifier ?? hub.key).lowercased()
        let title = hub.title.lowercased()
        let type = (hub.type ?? "").lowercased()
        let blob = id + " " + title + " " + type

        if blob.contains("continue") || blob.contains("on.deck") || blob.contains("ondeck")
            || blob.contains("inprogress") || blob.contains("in progress") {
            return .continueWatching
        }
        if blob.contains("recently.added") || blob.contains("recentlyadded")
            || blob.contains("recently added") || blob.contains("newest") {
            return .recentlyAdded
        }
        if blob.contains("recently.played") || blob.contains("recently.viewed")
            || blob.contains("recently played") || blob.contains("recently viewed")
            || blob.contains("watch.again") {
            return .recentlyPlayed
        }
        if type == "movie" || blob.contains("movie") {
            return .movies
        }
        if type == "show" || type == "episode" || blob.contains("tv") || blob.contains("show")
            || blob.contains("series") || blob.contains("episode") {
            return .tv
        }
        if type == "artist" || type == "album" || type == "track"
            || blob.contains("music") || blob.contains("artist") || blob.contains("album") {
            return .music
        }
        return .other
    }

    func filtered(_ hubs: [PlexHub]) -> [PlexHub] {
        hubs.compactMap { hub in
            let cat = Self.category(for: hub)
            guard isEnabled(cat) else { return nil }
            var copy = hub
            if maxItemsPerHub > 0, copy.items.count > maxItemsPerHub {
                copy.items = Array(copy.items.prefix(maxItemsPerHub))
            }
            return copy.items.isEmpty ? nil : copy
        }
    }
}

@MainActor
final class HomeSettingsStore {
    static let shared = HomeSettingsStore()

    private let defaults: UserDefaults
    private enum Keys {
        static let continueWatching = "home.showContinueWatching"
        static let recentlyAdded = "home.showRecentlyAdded"
        static let recentlyPlayed = "home.showRecentlyPlayed"
        static let movies = "home.showMovies"
        static let tv = "home.showTV"
        static let music = "home.showMusic"
        static let other = "home.showOther"
        static let maxItems = "home.maxItemsPerHub"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferences: HomeDisplayPreferences {
        get {
            HomeDisplayPreferences(
                showContinueWatching: defaults.object(forKey: Keys.continueWatching) as? Bool ?? true,
                showRecentlyAdded: defaults.object(forKey: Keys.recentlyAdded) as? Bool ?? true,
                showRecentlyPlayed: defaults.object(forKey: Keys.recentlyPlayed) as? Bool ?? true,
                showMovies: defaults.object(forKey: Keys.movies) as? Bool ?? true,
                showTV: defaults.object(forKey: Keys.tv) as? Bool ?? true,
                showMusic: defaults.object(forKey: Keys.music) as? Bool ?? true,
                showOther: defaults.object(forKey: Keys.other) as? Bool ?? true,
                maxItemsPerHub: defaults.object(forKey: Keys.maxItems) as? Int ?? 20
            )
        }
        set {
            defaults.set(newValue.showContinueWatching, forKey: Keys.continueWatching)
            defaults.set(newValue.showRecentlyAdded, forKey: Keys.recentlyAdded)
            defaults.set(newValue.showRecentlyPlayed, forKey: Keys.recentlyPlayed)
            defaults.set(newValue.showMovies, forKey: Keys.movies)
            defaults.set(newValue.showTV, forKey: Keys.tv)
            defaults.set(newValue.showMusic, forKey: Keys.music)
            defaults.set(newValue.showOther, forKey: Keys.other)
            defaults.set(newValue.maxItemsPerHub, forKey: Keys.maxItems)
        }
    }
}
