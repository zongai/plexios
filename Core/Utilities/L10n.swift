import Foundation

/// Typed access to `Localizable.strings` keys.
enum L10n {
    // MARK: Tabs
    static var home: String { String(localized: "tab.home") }
    static var libraries: String { String(localized: "tab.libraries") }
    static var collections: String { String(localized: "tab.collections") }
    static var playlists: String { String(localized: "tab.playlists") }
    static var search: String { String(localized: "tab.search") }
    static var settings: String { String(localized: "tab.settings") }
    static var more: String { String(localized: "tab.more") }

    // MARK: Common
    static var ok: String { String(localized: "common.ok") }
    static var cancel: String { String(localized: "common.cancel") }
    static var close: String { String(localized: "common.close") }
    static var retry: String { String(localized: "common.retry") }
    static var loading: String { String(localized: "common.loading") }
    static var starting: String { String(localized: "common.starting") }
    static var refresh: String { String(localized: "common.refresh") }
    static var off: String { String(localized: "common.off") }
    static var errorTitle: String { String(localized: "common.error") }
    static var notFound: String { String(localized: "common.not_found") }
    static var noServer: String { String(localized: "common.no_server") }

    // MARK: Home
    static var homeEmptyTitle: String { String(localized: "home.empty.title") }
    static var homeEmptySubtitle: String { String(localized: "home.empty.subtitle") }
    static var connectingServer: String { String(localized: "home.connecting") }
    static var findingConnection: String { String(localized: "home.finding_connection") }
    static var noServersTitle: String { String(localized: "home.no_servers.title") }
    static var noServersSubtitle: String { String(localized: "home.no_servers.subtitle") }

    // MARK: Sign-in
    static var signInTitle: String { String(localized: "signin.title") }
    static var signInSubtitle: String { String(localized: "signin.subtitle") }
    static var signInCodeHint: String { String(localized: "signin.code_hint") }
    static var copyCode: String { String(localized: "signin.copy_code") }
    static var copied: String { String(localized: "signin.copied") }
    static var openLink: String { String(localized: "signin.open_link") }
    static var signInWaiting: String { String(localized: "signin.waiting") }
    static var signInExpired: String { String(localized: "signin.expired") }
    static var getCode: String { String(localized: "signin.generate") }

    // MARK: Detail
    static var play: String { String(localized: "detail.play") }
    static var resume: String { String(localized: "detail.resume") }
    static var markWatched: String { String(localized: "detail.watched") }
    static var favorite: String { String(localized: "detail.favorite") }
    static var unfavorite: String { String(localized: "detail.unfavorite") }
    static var seasons: String { String(localized: "detail.seasons") }
    static var season: String { String(localized: "detail.season") }
    static func episodesCount(_ n: Int) -> String {
        String(format: String(localized: "detail.episodes_count"), n)
    }
    static var genres: String { String(localized: "detail.genres") }
    static var director: String { String(localized: "detail.director") }
    static var writers: String { String(localized: "detail.writers") }
    static var cast: String { String(localized: "detail.cast") }
    static var media: String { String(localized: "detail.media") }
    static var noEpisodes: String { String(localized: "detail.no_episodes") }

    // MARK: Player
    static var playerPlay: String { String(localized: "player.play") }
    static var playerPause: String { String(localized: "player.pause") }
    static var playerClose: String { String(localized: "player.close") }
    static var airPlay: String { String(localized: "player.airplay") }
    static var audioTracks: String { String(localized: "player.audio") }
    static var subtitles: String { String(localized: "player.subtitles") }
    static var speed: String { String(localized: "player.speed") }
    static var aspectRatio: String { String(localized: "player.aspect") }
    static var back10: String { String(localized: "player.back_10") }
    static var forward10: String { String(localized: "player.forward_10") }
    static var loadingPlayback: String { String(localized: "player.loading") }
    static var playbackPosition: String { String(localized: "player.position") }

    // MARK: Settings
    static var settingsPlayback: String { String(localized: "settings.playback") }
    static var settingsCache: String { String(localized: "settings.cache") }
    static var settingsAbout: String { String(localized: "settings.about") }
    static var clearCache: String { String(localized: "settings.clear_cache") }
    static var preferSystemPlayer: String { String(localized: "settings.prefer_system_player") }
    static var allowVLC: String { String(localized: "settings.allow_vlc") }
    static var languageNote: String { String(localized: "settings.language_note") }
    static var version: String { String(localized: "settings.version") }

    static var searchPlaceholder: String { String(localized: "search.placeholder") }
    static var noResults: String { String(localized: "search.no_results") }
    static var librariesEmpty: String { String(localized: "libraries.empty") }
}
