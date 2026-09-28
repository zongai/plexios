import Foundation
import OSLog

/// Central logging facade. Categories mirror the architecture document.
/// Tokens and other secrets must never be logged — use `redact` helpers.
struct LogRouter: Sendable {
    let app: Logger
    let network: Logger
    let plex: Logger
    let playback: Logger
    let cache: Logger
    let ui: Logger
    let database: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.plexios.app") {
        app = Logger(subsystem: subsystem, category: "app")
        network = Logger(subsystem: subsystem, category: "network")
        plex = Logger(subsystem: subsystem, category: "plex")
        playback = Logger(subsystem: subsystem, category: "playback")
        cache = Logger(subsystem: subsystem, category: "cache")
        ui = Logger(subsystem: subsystem, category: "ui")
        database = Logger(subsystem: subsystem, category: "database")
    }
}

// MARK: - Redaction

enum LogRedaction {
    /// Replaces token-like query/header values before logging URLs or headers.
    static func redact(_ value: String) -> String {
        var result = value

        // X-Plex-Token query or header style
        let patterns = [
            #"[?&]X-Plex-Token=[^&\s]+"#,
            #"X-Plex-Token:\s*\S+"#,
            #"authToken[=:]\s*\S+"#,
            #"accessToken[=:]\s*\S+"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: "[REDACTED]"
                )
            }
        }

        return result
    }

    static func redactURL(_ url: URL) -> String {
        redact(url.absoluteString)
    }
}
