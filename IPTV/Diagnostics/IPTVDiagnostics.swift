import Foundation

/// Runtime diagnostics for IPTV playback (safe for UI HUD; URLs redacted).
@Observable
@MainActor
final class IPTVDiagnostics {
    var channelName: String = ""
    var sourceName: String = ""
    var qualityLabel: String = ""
    var backend: String = ""
    var sessionState: String = ""
    var redactedURL: String = ""
    var estimatedThroughputMbps: Double?
    var sourceSwitchCount: Int = 0
    var bufferEvents: Int = 0
    var lastError: String?
    var startupMs: Int?
    var isVisible: Bool = false

    private var playStartedAt: Date?

    func reset(channel: String, source: IPTVSource, backend: String) {
        channelName = channel
        sourceName = source.name ?? source.quality.displayName
        qualityLabel = source.quality.displayName
        self.backend = backend
        sessionState = "loading"
        redactedURL = Self.redact(source.streamURLString)
        sourceSwitchCount = 0
        bufferEvents = 0
        lastError = nil
        startupMs = nil
        playStartedAt = Date()
        estimatedThroughputMbps = nil
    }

    func markPlaying() {
        if let start = playStartedAt, startupMs == nil {
            startupMs = Int(Date().timeIntervalSince(start) * 1000)
        }
        sessionState = "playing"
    }

    func markBuffering() {
        bufferEvents += 1
        sessionState = "buffering"
    }

    func markError(_ message: String) {
        lastError = message
        sessionState = "error"
    }

    func markSourceSwitch(to source: IPTVSource) {
        sourceSwitchCount += 1
        sourceName = source.name ?? source.quality.displayName
        qualityLabel = source.quality.displayName
        redactedURL = Self.redact(source.streamURLString)
        playStartedAt = Date()
        startupMs = nil
    }

    static func redact(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return String(urlString.prefix(48)) + "…"
        }
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map { item in
                let key = item.name.lowercased()
                if key.contains("token") || key.contains("auth") || key.contains("key")
                    || key.contains("password") || key.contains("user") {
                    return URLQueryItem(name: item.name, value: "********")
                }
                return item
            }
        }
        var s = components.string ?? urlString
        if s.count > 96 {
            s = String(s.prefix(96)) + "…"
        }
        return s
    }
}
