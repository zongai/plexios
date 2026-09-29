import Foundation

/// Home screen visibility driven by **actual library sections** on the server,
/// plus a few global personal rows (Continue Watching, etc.).
struct HomeDisplayPreferences: Sendable, Equatable {
    /// Library section keys that are disabled (missing key = enabled by default).
    var disabledLibraryKeys: Set<String>
    /// Personal / cross-library rows from `/hubs`.
    var showContinueWatching: Bool
    var showRecentlyPlayed: Bool
    var maxItemsPerHub: Int

    static let `default` = HomeDisplayPreferences(
        disabledLibraryKeys: [],
        showContinueWatching: true,
        showRecentlyPlayed: true,
        maxItemsPerHub: 20
    )

    func isLibraryEnabled(_ key: String) -> Bool {
        !disabledLibraryKeys.contains(key)
    }

    mutating func setLibrary(_ key: String, enabled: Bool) {
        if enabled {
            disabledLibraryKeys.remove(key)
        } else {
            disabledLibraryKeys.insert(key)
        }
    }

    enum PersonalKind {
        case continueWatching
        case recentlyAdded
        case recentlyPlayed
        case none
    }

    static func personalKind(for hub: PlexHub) -> PersonalKind {
        let id = (hub.hubIdentifier ?? hub.key).lowercased()
        let title = hub.title.lowercased()
        let blob = id + " " + title
        if blob.contains("continue") || blob.contains("on.deck") || blob.contains("ondeck")
            || blob.contains("inprogress") || blob.contains("in progress") {
            return .continueWatching
        }
        if blob.contains("recently.added") || blob.contains("recently added")
            || blob.contains("recentlyadded") || blob.contains("newest") {
            return .recentlyAdded
        }
        if blob.contains("recently.played") || blob.contains("recently.viewed")
            || blob.contains("recently played") || blob.contains("recently viewed")
            || blob.contains("watch.again") {
            return .recentlyPlayed
        }
        return .none
    }

    static func sectionKeys(for hub: PlexHub, libraries: [PlexLibrary]) -> Set<String> {
        var keys = Set<String>()
        for item in hub.items {
            if let sid = item.librarySectionID, !sid.isEmpty {
                keys.insert(sid)
            }
        }
        let id = hub.hubIdentifier ?? hub.key
        for lib in libraries {
            if id.hasSuffix(".\(lib.key)") || id.contains(".\(lib.key).") || id.hasSuffix("/\(lib.key)") {
                keys.insert(lib.key)
            }
            if hub.title.localizedCaseInsensitiveContains(lib.title) {
                keys.insert(lib.key)
            }
        }
        return keys
    }

    static func matchesLibraryType(_ hub: PlexHub, library: PlexLibrary) -> Bool {
        let type = (hub.type ?? hub.items.first?.type.rawValue ?? "").lowercased()
        switch library.type {
        case .movie:
            return type == "movie" || hub.items.contains { $0.type == .movie }
        case .show:
            return type == "show" || type == "episode" || type == "season"
                || hub.items.contains { [.show, .episode, .season].contains($0.type) }
        case .artist:
            return type == "artist" || type == "album" || type == "track"
                || hub.items.contains { [.artist, .album, .track].contains($0.type) }
        case .photo:
            return type == "photo"
        case .mixed, .unknown:
            return true
        }
    }

    func filtered(_ hubs: [PlexHub], libraries: [PlexLibrary]) -> [PlexHub] {
        let enabledLibraries = libraries.filter { isLibraryEnabled($0.key) }
        let enabledKeys = Set(enabledLibraries.map(\.key))

        // Merge Continue Watching / Recently Played only. Recently Added stays per-library shelf.
        var continueItems: [PlexMetadata] = []
        var continueHubTemplate: PlexHub?
        var playedItems: [PlexMetadata] = []
        var playedHubTemplate: PlexHub?
        var other: [PlexHub] = []

        for hub in hubs {
            switch Self.personalKind(for: hub) {
            case .continueWatching:
                guard showContinueWatching else { continue }
                if continueHubTemplate == nil { continueHubTemplate = hub }
                continueItems.append(contentsOf: hub.items)
            case .recentlyPlayed:
                guard showRecentlyPlayed else { continue }
                if playedHubTemplate == nil { playedHubTemplate = hub }
                playedItems.append(contentsOf: hub.items)
            case .recentlyAdded, .none:
                other.append(hub)
            }
        }

        var result: [PlexHub] = []

        if var template = continueHubTemplate {
            template.items = Self.dedupeItems(continueItems, enabledKeys: enabledKeys, max: maxItemsPerHub)
            if !template.items.isEmpty {
                result.append(template)
            }
        }

        for hub in other {
            switch Self.personalKind(for: hub) {
            case .continueWatching, .recentlyPlayed:
                continue
            case .recentlyAdded:
                // Keep each Recently Added shelf; still respect library toggles.
                if !libraries.isEmpty {
                    let sectionKeys = Self.sectionKeys(for: hub, libraries: libraries)
                    if !sectionKeys.isEmpty {
                        guard !sectionKeys.isDisjoint(with: enabledKeys) else { continue }
                    }
                }
            case .none:
                if !libraries.isEmpty {
                    let sectionKeys = Self.sectionKeys(for: hub, libraries: libraries)
                    if !sectionKeys.isEmpty {
                        guard !sectionKeys.isDisjoint(with: enabledKeys) else { continue }
                    } else {
                        let typeMatch = enabledLibraries.contains { Self.matchesLibraryType(hub, library: $0) }
                        guard typeMatch else { continue }
                    }
                }
            }

            var copy = hub
            copy.items = Self.dedupeItems(copy.items, enabledKeys: enabledKeys, max: maxItemsPerHub)
            if !copy.items.isEmpty {
                result.append(copy)
            }
        }

        if var template = playedHubTemplate {
            template.items = Self.dedupeItems(playedItems, enabledKeys: enabledKeys, max: maxItemsPerHub)
            if !template.items.isEmpty {
                result.append(template)
            }
        }

        return result
    }

    /// Stable order, unique by ratingKey; optional library filter and max count.
    private static func dedupeItems(
        _ items: [PlexMetadata],
        enabledKeys: Set<String>,
        max: Int
    ) -> [PlexMetadata] {
        var seen = Set<String>()
        var out: [PlexMetadata] = []
        for item in items {
            if item.ratingKey.isEmpty { continue }
            if !enabledKeys.isEmpty, let sid = item.librarySectionID, !enabledKeys.contains(sid) {
                continue
            }
            // Episodes of the same show: keep each episode (different ratingKey).
            // Identical ratingKey from multiple hubs is dropped.
            if seen.contains(item.ratingKey) { continue }
            seen.insert(item.ratingKey)
            out.append(item)
            if max > 0, out.count >= max { break }
        }
        return out
    }
}

@MainActor
final class HomeSettingsStore {
    static let shared = HomeSettingsStore()

    private let defaults: UserDefaults
    private enum Keys {
        static let disabledLibraries = "home.disabledLibraryKeys"
        static let continueWatching = "home.showContinueWatching"
        static let recentlyPlayed = "home.showRecentlyPlayed"
        static let maxItems = "home.maxItemsPerHub"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferences: HomeDisplayPreferences {
        get {
            let disabled = Set(defaults.stringArray(forKey: Keys.disabledLibraries) ?? [])
            return HomeDisplayPreferences(
                disabledLibraryKeys: disabled,
                showContinueWatching: defaults.object(forKey: Keys.continueWatching) as? Bool ?? true,
                showRecentlyPlayed: defaults.object(forKey: Keys.recentlyPlayed) as? Bool ?? true,
                maxItemsPerHub: defaults.object(forKey: Keys.maxItems) as? Int ?? 20
            )
        }
        set {
            defaults.set(Array(newValue.disabledLibraryKeys), forKey: Keys.disabledLibraries)
            defaults.set(newValue.showContinueWatching, forKey: Keys.continueWatching)
            defaults.set(newValue.showRecentlyPlayed, forKey: Keys.recentlyPlayed)
            defaults.set(newValue.maxItemsPerHub, forKey: Keys.maxItems)
        }
    }
}
