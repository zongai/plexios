import Foundation

/// Holds decoded cues and resolves active subtitles at a media time.
final class SubtitleTrackController: @unchecked Sendable {
    private let lock = NSLock()
    private var cues: [TimedSubtitle] = []
    private var style = SubtitleStyle()

    var subtitleStyle: SubtitleStyle {
        get { lock.lock(); defer { lock.unlock() }; return style }
        set { lock.lock(); style = newValue; lock.unlock() }
    }

    func load(_ cues: [TimedSubtitle]) {
        lock.lock()
        self.cues = cues.sorted { $0.startMs < $1.startMs }
        lock.unlock()
    }

    func append(_ more: [TimedSubtitle]) {
        lock.lock()
        cues.append(contentsOf: more)
        cues.sort { $0.startMs < $1.startMs }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        cues.removeAll()
        lock.unlock()
    }

    func activeCues(atMs mediaTimeMs: Int64) -> [TimedSubtitle] {
        lock.lock()
        defer { lock.unlock() }
        let t = mediaTimeMs + style.delayMs
        return cues.filter { t >= $0.startMs && t < $0.endMs }
    }

    func event(atMs mediaTimeMs: Int64) -> SubtitleCueEvent {
        SubtitleCueEvent(active: activeCues(atMs: mediaTimeMs), mediaTimeMs: mediaTimeMs)
    }

    /// Load full file data (sidecar).
    func loadFile(data: Data, format: SubtitleFormat) throws {
        let decoder = try SubtitleDecoderFactory.make(format: format)
        let parsed = try decoder.decode(data: data, encoding: .utf8)
        load(parsed)
    }

    /// Fetch Plex stream key URL (external subtitle).
    func loadFromURL(_ url: URL, headers: [String: String], format: SubtitleFormat) async throws {
        var request = URLRequest(url: url)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SubtitleDecoderError.parseFailed("HTTP \(http.statusCode)")
        }
        try loadFile(data: data, format: format)
    }
}
