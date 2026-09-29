import Foundation

/// Locale-aware labels for media cards / hub rails (Home, library shelves).
enum MediaDisplayFormatting {
    /// Hub section title: prefer localized personal rows; else server title.
    static func hubTitle(_ hub: PlexHub) -> String {
        switch HomeDisplayPreferences.personalKind(for: hub) {
        case .continueWatching:
            return String(localized: "home.pref.continue")
        case .recentlyAdded:
            return String(localized: "home.pref.recently_added")
        case .recentlyPlayed:
            return String(localized: "home.pref.recently_played")
        case .none:
            break
        }
        // Server may still send English; map common patterns
        let blob = ((hub.hubIdentifier ?? hub.key) + " " + hub.title).lowercased()
        if blob.contains("recently.added") || blob.contains("recently added")
            || blob.contains("recentlyadded") {
            return String(localized: "home.pref.recently_added")
        }
        if blob.contains("continue") || blob.contains("on.deck") || blob.contains("on deck") {
            return String(localized: "home.pref.continue")
        }
        return hub.title
    }

    /// Primary title on a shelf card.
    static func cardTitle(for item: PlexMetadata, wide: Bool) -> String {
        if wide, item.type == .episode {
            return item.grandparentTitle ?? item.title
        }
        if item.type == .episode, item.grandparentTitle != nil {
            // Poster-style: still prefer show name for consistency on mixed rails
            return item.grandparentTitle ?? item.title
        }
        // Season cards in hubs: show the series name, not "Season 1" / "季 1"
        if item.type == .season {
            return item.parentTitle ?? item.title
        }
        return item.title
    }

    /// Secondary line under the title.
    /// TV shelves may mix `show` and `season` items; always prefer episode counts
    /// so the bottom line is consistent (not "16 集" next to "季 1").
    static func cardSubtitle(for item: PlexMetadata, wide: Bool) -> String? {
        switch item.type {
        case .movie:
            return item.year.map(String.init)
        case .show:
            if let leaf = item.leafCount, leaf > 0 {
                return String(format: String(localized: "media.episode_count"), locale: Locale.current, leaf)
            }
            if let seasons = item.childCount, seasons > 0 {
                return String(format: String(localized: "media.season_count"), locale: Locale.current, seasons)
            }
            return item.year.map(String.init)
        case .season:
            // Prefer episode count within the season; else "Season N"
            if let leaf = item.leafCount, leaf > 0 {
                return String(format: String(localized: "media.episode_count"), locale: Locale.current, leaf)
            }
            if let idx = item.index {
                return String(format: String(localized: "media.season_n"), locale: Locale.current, idx)
            }
            return item.year.map(String.init)
        case .episode:
            let code = seasonEpisodeCode(season: item.parentIndex, episode: item.index)
            let epTitle = item.title
            if wide {
                if let code, !epTitle.isEmpty {
                    return "\(code)\(listSeparator)\(epTitle)"
                }
                return code ?? (epTitle.isEmpty ? nil : epTitle)
            }
            // Poster rail: season/episode + optional episode title
            if let code {
                if !epTitle.isEmpty, epTitle != item.grandparentTitle {
                    return "\(code)\(listSeparator)\(epTitle)"
                }
                return code
            }
            return epTitle.isEmpty ? item.year.map(String.init) : epTitle
        case .album:
            return item.parentTitle ?? item.year.map(String.init)
        case .track:
            return item.grandparentTitle ?? item.parentTitle
        default:
            return item.year.map(String.init)
        }
    }

    /// e.g. en "S1 · E2", zh "第1季第2集", ja "S1 第2話"
    static func seasonEpisodeCode(season: Int?, episode: Int?) -> String? {
        guard season != nil || episode != nil else { return nil }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"

        switch lang {
        case "zh":
            var parts: [String] = []
            if let s = season {
                parts.append(String(format: String(localized: "media.season_n"), locale: Locale.current, s))
            }
            if let e = episode {
                parts.append(String(format: String(localized: "media.episode_n"), locale: Locale.current, e))
            }
            return parts.joined()
        case "ja":
            var parts: [String] = []
            if let s = season { parts.append("S\(s)") }
            if let e = episode {
                parts.append(String(format: String(localized: "media.episode_n"), locale: Locale.current, e))
            }
            return parts.joined(separator: " ")
        case "ko":
            var parts: [String] = []
            if let s = season {
                parts.append(String(format: String(localized: "media.season_n"), locale: Locale.current, s))
            }
            if let e = episode {
                parts.append(String(format: String(localized: "media.episode_n"), locale: Locale.current, e))
            }
            return parts.joined(separator: " ")
        default:
            var parts: [String] = []
            if let s = season { parts.append("S\(s)") }
            if let e = episode { parts.append("E\(e)") }
            return parts.joined(separator: " · ")
        }
    }

    /// Separator between list fragments; CJK prefers full-width or space.
    private static var listSeparator: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "zh", "ja", "ko":
            return " "
        default:
            return " · "
        }
    }
}
