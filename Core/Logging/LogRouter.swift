import Foundation
import OSLog

/// Central logging facade. Categories mirror the architecture document.
/// Every message is mirrored to `FileLogStore` (durable) and `Logger` (Console).
struct LogRouter: Sendable {
    let app: CategoryLogger
    let network: CategoryLogger
    let plex: CategoryLogger
    let playback: CategoryLogger
    let cache: CategoryLogger
    let ui: CategoryLogger
    let database: CategoryLogger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.plexios.app") {
        // Touch store early so crash hooks install at process start.
        _ = FileLogStore.shared
        app = CategoryLogger(subsystem: subsystem, category: "app")
        network = CategoryLogger(subsystem: subsystem, category: "network")
        plex = CategoryLogger(subsystem: subsystem, category: "plex")
        playback = CategoryLogger(subsystem: subsystem, category: "playback")
        cache = CategoryLogger(subsystem: subsystem, category: "cache")
        ui = CategoryLogger(subsystem: subsystem, category: "ui")
        database = CategoryLogger(subsystem: subsystem, category: "database")
    }
}

/// Dual-writes to OSLog + on-disk store. Call sites keep `logger.playback.info("…")`.
struct CategoryLogger: Sendable {
    private let os: Logger
    private let category: String

    init(subsystem: String, category: String) {
        self.os = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func debug(_ message: String) {
        os.debug("\(message, privacy: .public)")
        FileLogStore.shared.append(level: .debug, category: category, message: message)
    }

    func info(_ message: String) {
        os.info("\(message, privacy: .public)")
        FileLogStore.shared.append(level: .info, category: category, message: message)
    }

    func notice(_ message: String) {
        os.notice("\(message, privacy: .public)")
        FileLogStore.shared.append(level: .notice, category: category, message: message)
    }

    func warning(_ message: String) {
        os.warning("\(message, privacy: .public)")
        FileLogStore.shared.append(level: .warning, category: category, message: message)
    }

    func error(_ message: String) {
        os.error("\(message, privacy: .public)")
        // Errors flush immediately so a follow-up crash still retains them.
        FileLogStore.shared.appendAndFlush(level: .error, category: category, message: message)
    }

    func fault(_ message: String) {
        os.fault("\(message, privacy: .public)")
        FileLogStore.shared.appendAndFlush(level: .fault, category: category, message: message)
    }
}

// MARK: - Redaction

enum LogRedaction {
    /// Replaces token-like query/header values before logging URLs or headers.
    static func redact(_ value: String) -> String {
        var result = value

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
