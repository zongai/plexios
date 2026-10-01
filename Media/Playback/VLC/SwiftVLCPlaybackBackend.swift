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
/// switch with minimal churn. APIs used here are from SwiftVLC **v1.0.0**
/// (`Player.swift`, `Media.swift`, `Player+Seek.swift`, README).
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
    private var observationTask: Task<Void, Never>?
#endif

    private var httpHeaders: [String: String] = [:]
    private var attachedExternalFileURLs: [URL] = []

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

        httpHeaders = headers
        _ = preferredSubtitlePlexId
        _ = preferredAudioPlexId

        let media = try Media(url: url)
        media.addOption(":network-caching=1500")
        media.addOption(":http-reconnect")
        media.addOption(":sub-autodetect-file")
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

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            self.syncTracksFromPlayer()
            self.onTracksUpdated?()
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
        } catch {
            onError?(String(describing: error))
        }
#endif
    }

    func setVolume(_ linear: Float) {
#if canImport(SwiftVLC)
        let clamped = max(0, min(2, linear))
        // Volume is a typed wrapper; construct via raw if available.
        if let vol = Volume(rawValue: clamped) {
            try? player?.setAudioVolume(vol)
        }
#endif
    }

    func setRate(_ rate: Float) {
        self.rate = rate
#if canImport(SwiftVLC)
        if let pr = PlaybackRate(rawValue: rate) {
            try? player?.setPlaybackRate(pr)
        }
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

#if canImport(SwiftVLC)
    private func startEventConsumer(on player: Player) {
        eventTask?.cancel()
        observationTask?.cancel()

        observationTask = Task { @MainActor [weak self] in
            var lastPos: Int64 = -1
            var lastDur: Int64 = -1
            while !Task.isCancelled {
                guard let self, let p = self.player, p === player else { break }
                let pos = durationMilliseconds(p.currentTime)
                let dur = p.duration.map(durationMilliseconds) ?? 0
                self.positionMs = pos
                self.durationMs = dur
                if pos != lastPos || dur != lastDur {
                    lastPos = pos
                    lastDur = dur
                    self.onTimeChange?(pos, dur)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        eventTask = Task { @MainActor [weak self] in
            for await st in player.stateTransitions {
                guard let self, self.player === player else { break }
                self.applyPlayerState(st, player: player)
            }
        }
    }

    private func durationMilliseconds(_ d: Duration) -> Int64 {
        let c = d.components
        return Int64(c.seconds * 1000) + Int64(c.attoseconds / 1_000_000_000_000_000)
    }

    private func applyPlayerState(_ st: PlayerState, player: Player) {
        switch st {
        case .opening, .buffering:
            state = .buffering
            onStateChange?(.buffering)
        case .playing:
            state = .playing
            onStateChange?(.playing)
        case .paused:
            state = .paused
            onStateChange?(.paused)
        case .stopped:
            if player.didReachEnd {
                onEnded?()
            }
            state = .stopped
            onStateChange?(.stopped)
        case .error:
            state = .failed
            onStateChange?(.failed)
            onError?("SwiftVLC player error")
        case .idle, .stopping:
            break
        @unknown default:
            break
        }
        syncTracksFromPlayer()
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
        onTracksUpdated?()
    }

    private func stopInternal() async {
        eventTask?.cancel()
        eventTask = nil
        observationTask?.cancel()
        observationTask = nil
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
            return .fill
        }
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
