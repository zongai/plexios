import Foundation
import OSLog

/// Lightweight timing helpers for startup and cache diagnostics.
enum PerformanceSignpost {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.plexios.app", category: "performance")

    static func begin(_ name: StaticString) {
        os_signpost(.begin, log: log, name: name)
    }

    static func end(_ name: StaticString) {
        os_signpost(.end, log: log, name: name)
    }

    /// Measures an async body and logs duration via Logger.
    static func measure<T>(
        _ label: String,
        logger: LogRouter,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let start = ContinuousClock.now
        defer {
            let ms = start.duration(to: .now).milliseconds
            logger.app.debug("⏱ \(label): \(ms) ms")
        }
        return try await body()
    }
}

private extension Duration {
    var milliseconds: Int64 {
        let components = self.components
        return components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}
