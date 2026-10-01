import Foundation
import SwiftUI

#if canImport(SwiftVLC)
import SwiftVLC
private enum SwiftVLCImport { static let available = true }
#else
private enum SwiftVLCImport { static let available = false }
#endif

/// SwiftVLC (libVLC 4) Direct Play backend.
///
/// Surface mirrors `VLCPlaybackBackend` so `PlaybackEngine` / Player UI can
/// switch with minimal churn. APIs from SwiftVLC **v1.0.0**:
/// `Player.swift`, `Media.swift`, `Player+Seek.swift`, `PlaybackValues.swift`,
/// `PlayerEvent.swift`.
@MainActor
final class SwiftVLCPlaybackBackend: NSObject {
    nonisolated static var isLinked: Bool { SwiftVLCImport.available }

    let backendKind: PlaybackBackend = .swiftVLC
    private(set) var state: MediaEngineSessionState = .idle
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var rate: Float = 1.0

    private(set) var audioTracks: [(index: Int, name: String)] = []
    private(set) var subtitleTracks: [(index: Int, name: String)] = []
    private(set) var selectedAudioIndex: Int = -1
    private(set) var selectedSubtitleIndex: Int = -1

    var onStateChange: ((MediaEngineSessionState) -> Void)?
    var onTimeChange: ((Int64, Int64) -> Void)?
    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    var onTracksUpdated: (() -> Void)?
    var onThroughputMbps: ((Double) -> Void)?
    private(set) var estimatedThroughputMbps: Double?

    private(set) var aspectMode: VideoAspectMode = .fit

    var currentVideoSize: CGSize {
#if canImport(SwiftVLC)
        guard let player else { return .zero }
        if let track = player.videoTracks.first(where: \.isSelected)
            ?? player.videoTracks.first,
           let w = track.width, let h = track.height, w > 0, h > 0 {
            return CGSize(width: CGFloat(w), height: CGFloat(h))
        }
#endif
        return .zero
    }

#if canImport(SwiftVLC)
    private(set) var player: Player?
    private var eventTask: Task<Void, Never>?
#endif

    private var httpHeaders: [String: String] = [:]
    private var attachedExternalFileURLs: [URL] = []
    /// Buffer was below full while we last reported buffering (for exit-to-playing).
    private var wasBuffering = false

    func rebindDrawable() {}
    func rebindDrawablePreservingAspect() { rebindDrawable() }

    func setAspectMode(_ mode: VideoAspectMode) {
        aspectMode = mode
#if canImport(SwiftVLC)
        player?.aspectRatio = Self.mapAspect(mode)
#endif
    }

    func prepare(
        url: URL,
        headers: [String: String],
        startPositionMs: Int64,
        externalSubtitles: [URL] = [],
        preferredSubtitlePlexId: Int? = nil,
        preferredAudioPlexId: Int? = nil,
        preferredAudioOrder: Int? = nil,
        preferredSubtitleOrder: Int? = nil,
        subtitleFontSize: Int = 16,
        forceSoftwareDecode: Bool = false
    ) async throws {
        guard SwiftVLCImport.available else {
            throw PlaybackFailure(
                stage: .unknown,
                reason: "SwiftVLC not linked",
                underlying: nil
            )
        }
#if canImport(SwiftVLC)
        await stopInternal()
        state = .loading
        onStateChange?(.loading)
        wasBuffering = false

        httpHeaders = headers
        _ = preferredSubtitlePlexId
        _ = preferredAudioPlexId

        let media = try Media(url: url)
        media.addOption(":network-caching=1500")
        media.addOption(":http-reconnect")
        media.addOption(":sub-autodetect-file")
        // Relative freetype size (legacy VLC); also map to SubtitleScale after play.
        media.addOption(":freetype-rel-fontsize=\(max(1, subtitleFontSize))")

        if forceSoftwareDecode {
            media.addOption(":avcodec-hw=none")
            media.addOption(":no-videotoolbox")
        }

        if let ua = headers["User-Agent"] ?? headers["user-agent"] {
            media.addOption(":http-user-agent=\(ua)")
        }

        for (i, subURL) in externalSubtitles.enumerated() {
            if let local = await downloadSubtitleToTemp(url: subURL) {
                try media.addSlave(from: local, type: .subtitle, priority: i == 0 ? 4 : 2)
            }
        }

        if let preferredAudioOrder, preferredAudioOrder >= 0 {
            media.addOption(":audio-track=\(preferredAudioOrder)")
        }
        if let preferredSubtitleOrder, preferredSubtitleOrder >= 0 {
            media.addOption(":sub-track=\(preferredSubtitleOrder)")
        }

        let newPlayer = Player()
        self.player = newPlayer
        newPlayer.aspectRatio = Self.mapAspect(aspectMode)
        // Map legacy freetype-rel-fontsize (~16 medium) toward SubtitleScale.
        // Smaller freetype-rel-fontsize → larger on-screen text.
        let scale = Self.subtitleScale(fromFreetypeRel: subtitleFontSize)
        newPlayer.setSubtitleScale(scale)

        startEventConsumer(on: newPlayer)

        try newPlayer.play(media)
        rate = 1.0
        state = .playing
        onStateChange?(.playing)

        if startPositionMs > 0 {
            do {
                try newPlayer.seek(to: .milliseconds(startPositionMs), fast: true)
            } catch {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    try? self.player?.seek(to: .milliseconds(startPositionMs), fast: true)
                }
            }
        }
#else
        throw PlaybackFailure(stage: .unknown, reason: "SwiftVLC not linked", underlying: nil)
#endif
    }

    func play() {
#if canImport(SwiftVLC)
        guard let player else { return }
        if player.state == .paused {
            player.resume()
        } else {
            try? player.play()
        }
        state = .playing
        onStateChange?(.playing)
#endif
    }

    func pause() {
#if canImport(SwiftVLC)
        player?.pause()
        state = .paused
        onStateChange?(.paused)
#endif
    }

    func stop() async {
        await stopInternal()
        state = .stopped
        onStateChange?(.stopped)
    }

    func seek(toMs ms: Int64) async {
#if canImport(SwiftVLC)
        guard let player else { return }
        do {
            try player.seek(to: .milliseconds(ms), fast: false)
            positionMs = ms
            onTimeChange?(positionMs, durationMs)
        } catch {
            onError?(String(describing: error))
        }
#endif
    }

    func setVolume(_ linear: Float) {
#if canImport(SwiftVLC)
        // Volume(_:) clamps to 0.0...2.0 (PlaybackValues.swift).
        try? player?.setAudioVolume(Volume(linear))
#endif
    }

    func setRate(_ rate: Float) {
        self.rate = rate
#if canImport(SwiftVLC)
        // PlaybackRate(_:) clamps to 0.25...4.0.
        try? player?.setPlaybackRate(PlaybackRate(rate))
#endif
    }

    func selectAudioIndex(_ index: Int) {
        selectedAudioIndex = index
#if canImport(SwiftVLC)
        guard let player, index >= 0, index < player.audioTracks.count else { return }
        player.selectedAudioTrack = player.audioTracks[index]
#endif
    }

    func selectSubtitleIndex(_ index: Int?) {
        selectedSubtitleIndex = index ?? -1
#if canImport(SwiftVLC)
        guard let player else { return }
        if let index, index >= 0, index < player.subtitleTracks.count {
            player.selectedSubtitleTrack = player.subtitleTracks[index]
        } else {
            player.selectedSubtitleTrack = nil
        }
#endif
    }

    /// Select audio by Plex stream metadata (language / order match).
    func applyPlexAudio(stream: PlexStream?, allAudioStreams: [PlexStream]) {
#if canImport(SwiftVLC)
        guard let stream, let player else { return }
        syncTracksFromPlayer()
        if let idx = matchAudioIndex(for: stream, all: allAudioStreams) {
            selectAudioIndex(idx)
            return
        }
        // Tracks may still be loading — retry once after ES events.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.syncTracksFromPlayer()
            if let idx = self.matchAudioIndex(for: stream, all: allAudioStreams) {
                self.selectAudioIndex(idx)
            }
        }
#else
        _ = stream
        _ = allAudioStreams
#endif
    }

    /// Select / clear subtitle by Plex stream. External sidecars are downloaded
    /// and attached via `Player.addExternalTrack` (Player.swift L809).
    func applyPlexSubtitle(
        stream: PlexStream?,
        allSubtitleStreams: [PlexStream],
        resolveExternalURL: @escaping (PlexStream) -> URL?
    ) {
#if canImport(SwiftVLC)
        guard let player else { return }
        guard let stream else {
            selectSubtitleIndex(nil)
            return
        }

        let isSidecar = stream.isExternal
            || (stream.key?.contains("/library/streams/") == true)

        if isSidecar, let remote = resolveExternalURL(stream) {
            Task { @MainActor in
                if let local = await self.downloadSubtitleToTemp(url: remote) {
                    do {
                        // Runtime external attach (Media.swift docs / Player.addExternalTrack).
                        try player.addExternalTrack(from: local, type: .subtitle, select: true)
                        try? await Task.sleep(for: .milliseconds(400))
                        self.syncTracksFromPlayer()
                        if let last = self.subtitleTracks.last {
                            self.selectSubtitleIndex(last.index)
                        }
                    } catch {
                        self.onError?(String(describing: error))
                    }
                }
            }
            return
        }

        syncTracksFromPlayer()
        if let idx = matchSubtitleIndex(for: stream, all: allSubtitleStreams) {
            selectSubtitleIndex(idx)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.syncTracksFromPlayer()
            if let idx = self.matchSubtitleIndex(for: stream, all: allSubtitleStreams) {
                self.selectSubtitleIndex(idx)
            }
        }
#else
        _ = stream
        _ = allSubtitleStreams
        _ = resolveExternalURL
#endif
    }

    /// Subtitle delay in milliseconds (positive = later).
    func setSubtitleDelayMs(_ ms: Int64) {
#if canImport(SwiftVLC)
        try? player?.setSubtitleDelay(.milliseconds(ms))
#endif
    }

#if canImport(SwiftVLC)
    private func startEventConsumer(on player: Player) {
        eventTask?.cancel()

        // Prefer event stream over polling: tracksChanged, endReached, buffering, time.
        // Use unbounded + filter so terminal events are not dropped (Player.swift docs).
        eventTask = Task { @MainActor [weak self] in
            let stream = player.events(
                policy: .unbounded,
                filter: { event in
                    switch event {
                    case .stateChanged, .timeChanged, .lengthChanged,
                         .tracksChanged, .endReached, .encounteredError,
                         .bufferingProgress, .mediaStopping:
                        return true
                    default:
                        return false
                    }
                }
            )
            for await event in stream {
                guard let self, self.player === player else { break }
                self.handleEvent(event, player: player)
            }
        }
    }

    private func handleEvent(_ event: PlayerEvent, player: Player) {
        switch event {
        case .stateChanged(let st):
            applyPlayerState(st, player: player)
        case .timeChanged(let time):
            positionMs = durationMilliseconds(time)
            onTimeChange?(positionMs, durationMs)
        case .lengthChanged(let length):
            durationMs = durationMilliseconds(length)
            onTimeChange?(positionMs, durationMs)
        case .tracksChanged:
            syncTracksFromPlayer()
            onTracksUpdated?()
        case .endReached:
            onEnded?()
            state = .stopped
            onStateChange?(.stopped)
        case .encounteredError:
            state = .failed
            onStateChange?(.failed)
            onError?("SwiftVLC player error")
        case .bufferingProgress(let progress):
            // progress is buffer fill 0...1 when reported this way; also use player.bufferFill.
            let fill = player.bufferFill > 0 ? player.bufferFill : progress
            if fill < 0.98, player.state == .playing || player.state == .buffering {
                if !wasBuffering {
                    wasBuffering = true
                    state = .buffering
                    onStateChange?(.buffering)
                }
            } else if wasBuffering {
                wasBuffering = false
                if player.state == .playing {
                    state = .playing
                    onStateChange?(.playing)
                }
            }
        case .mediaStopping:
            break
        default:
            break
        }
    }

    private func durationMilliseconds(_ d: Duration) -> Int64 {
        let c = d.components
        return Int64(c.seconds * 1000) + Int64(c.attoseconds / 1_000_000_000_000_000)
    }

    private func applyPlayerState(_ st: PlayerState, player: Player) {
        switch st {
        case .opening:
            state = .loading
            onStateChange?(.loading)
        case .buffering:
            wasBuffering = true
            state = .buffering
            onStateChange?(.buffering)
        case .playing:
            wasBuffering = false
            state = .playing
            onStateChange?(.playing)
        case .paused:
            state = .paused
            onStateChange?(.paused)
        case .stopped:
            // Natural end is also delivered as endReached; avoid double onEnded.
            if player.didReachEnd {
                // endReached handler may already have fired; keep state consistent.
                state = .stopped
                onStateChange?(.stopped)
            } else {
                state = .stopped
                onStateChange?(.stopped)
            }
        case .error:
            state = .failed
            onStateChange?(.failed)
            onError?("SwiftVLC player error")
        case .idle, .stopping:
            break
        @unknown default:
            break
        }
    }

    private func syncTracksFromPlayer() {
        guard let player else { return }
        audioTracks = player.audioTracks.enumerated().map { idx, t in
            let label = [t.language, t.name, t.trackDescription]
                .compactMap { $0 }
                .first { !$0.isEmpty } ?? "Audio \(idx + 1)"
            return (index: idx, name: label)
        }
        subtitleTracks = player.subtitleTracks.enumerated().map { idx, t in
            let label = [t.language, t.name, t.trackDescription]
                .compactMap { $0 }
                .first { !$0.isEmpty } ?? "Subtitle \(idx + 1)"
            return (index: idx, name: label)
        }
        if let sel = player.selectedAudioTrack,
           let idx = player.audioTracks.firstIndex(where: { $0.id == sel.id }) {
            selectedAudioIndex = idx
        }
        if let sel = player.selectedSubtitleTrack,
           let idx = player.subtitleTracks.firstIndex(where: { $0.id == sel.id }) {
            selectedSubtitleIndex = idx
        } else if player.selectedSubtitleTrack == nil {
            selectedSubtitleIndex = -1
        }
    }

    private func matchAudioIndex(for stream: PlexStream, all: [PlexStream]) -> Int? {
        // Prefer order among Plex audio list → same order in player tracks when counts align.
        if let order = all.firstIndex(where: { $0.id == stream.id }),
           order < audioTracks.count {
            return audioTracks[order].index
        }
        let lang = (stream.languageCode ?? stream.language ?? "").lowercased()
        if !lang.isEmpty {
            if let hit = player?.audioTracks.enumerated().first(where: {
                ($0.element.language ?? "").lowercased().hasPrefix(String(lang.prefix(2)))
            }) {
                return hit.offset
            }
        }
        return nil
    }

    private func matchSubtitleIndex(for stream: PlexStream, all: [PlexStream]) -> Int? {
        let embedded = all.filter { s in
            !(s.isExternal || (s.key?.contains("/library/streams/") == true))
        }
        if let order = embedded.firstIndex(where: { $0.id == stream.id }),
           order < subtitleTracks.count {
            return subtitleTracks[order].index
        }
        let lang = (stream.languageCode ?? stream.language ?? "").lowercased()
        if !lang.isEmpty {
            if let hit = player?.subtitleTracks.enumerated().first(where: {
                ($0.element.language ?? "").lowercased().hasPrefix(String(lang.prefix(2)))
            }) {
                return hit.offset
            }
        }
        return nil
    }

    private func stopInternal() async {
        eventTask?.cancel()
        eventTask = nil
        if let player {
            player.stop()
            try? await Task.sleep(for: .milliseconds(50))
        }
        player = nil
        audioTracks = []
        subtitleTracks = []
        selectedAudioIndex = -1
        selectedSubtitleIndex = -1
        positionMs = 0
        durationMs = 0
        wasBuffering = false
        for url in attachedExternalFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        attachedExternalFileURLs.removeAll()
    }

    private static func mapAspect(_ mode: VideoAspectMode) -> AspectRatio {
        switch mode {
        case .fit:
            return .default
        case .fill:
            return .fill
        case .stretch:
            // No pure stretch in AspectRatio; fill is closest documented behavior.
            return .fill
        }
    }

    /// Map legacy VLC freetype-rel-fontsize (smaller → larger text) to SubtitleScale.
    private static func subtitleScale(fromFreetypeRel rel: Int) -> SubtitleScale {
        // Medium default in app is ~16. Scale ≈ 16/rel, clamped by SubtitleScale.
        let base = 16.0
        let factor = Float(base / Double(max(1, rel)))
        return SubtitleScale(factor)
    }
#endif

    private func downloadSubtitleToTemp(url: URL) async -> URL? {
        let ext: String = {
            let path = url.path.lowercased()
            if path.hasSuffix(".ass") || path.hasSuffix(".ssa") { return "ass" }
            if path.hasSuffix(".vtt") { return "vtt" }
            return "srt"
        }()
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            for (k, v) in httpHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
            if request.value(forHTTPHeaderField: "X-Plex-Token") == nil,
               let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value {
                request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard !data.isEmpty else { return nil }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("plex-sub-\(UUID().uuidString).\(ext)")
            try data.write(to: tmp, options: .atomic)
            attachedExternalFileURLs.append(tmp)
            return tmp
        } catch {
            return nil
        }
    }
}
