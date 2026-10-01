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
/// Phase 1: scaffold only — compiles and exposes the same surface shape as
/// `VLCPlaybackBackend` so `PlaybackEngine` can later switch without UI churn.
/// Playback methods are no-ops / throw until Phase 2 wires `Player` + `VideoView`.
///
/// API names and behavior for the real implementation are taken from
/// SwiftVLC v1.0.0 sources (`Player.swift`, `Media.swift`) — not invented here.
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

    /// Pixel size of decoded video (0 until known). Used by container layout.
    var currentVideoSize: CGSize { .zero }

#if canImport(SwiftVLC)
    /// Owned SwiftVLC player. Created lazily in `prepare` (Phase 2+).
    private(set) var player: Player?
#endif

    func rebindDrawable() {
        // Phase 2+: VideoView owns the drawable lifecycle; no-op for now.
    }

    func rebindDrawablePreservingAspect() {
        rebindDrawable()
    }

    func setAspectMode(_ mode: VideoAspectMode) {
        aspectMode = mode
#if canImport(SwiftVLC)
        // Phase 2+: map VideoAspectMode → SwiftVLC.AspectRatio when wiring play.
#endif
    }

    /// Prepare media for playback. Phase 1 only validates linkage.
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
        // Phase 2 will:
        // - Media(url:) + addOption(":network-caching=…") etc. (Media.swift)
        // - media.addSlave for external subs (Media.addSlave)
        // - player.play(media) / seek (Player.swift)
        // Headers: SwiftVLC does not guarantee arbitrary HTTP header injection;
        // prefer query-token URLs until confirmed.
        _ = url
        _ = headers
        _ = startPositionMs
        _ = externalSubtitles
        _ = preferredSubtitlePlexId
        _ = preferredAudioPlexId
        _ = preferredAudioOrder
        _ = preferredSubtitleOrder
        _ = subtitleFontSize
        _ = forceSoftwareDecode

        state = .loading
        onStateChange?(.loading)
        throw PlaybackFailure(
            stage: .unknown,
            reason: "SwiftVLCPlaybackBackend Phase 1 scaffold — playback not wired yet",
            underlying: nil
        )
    }

    func play() {
        // Phase 2: try player?.play()
    }

    func pause() {
        // Phase 2: player?.pause()
    }

    func stop() async {
        state = .stopped
        onStateChange?(.stopped)
#if canImport(SwiftVLC)
        player = nil
#endif
    }

    func seek(toMs ms: Int64) async {
        _ = ms
        // Phase 2: try player?.seek(to:)
    }

    func setVolume(_ linear: Float) {
        _ = linear
        // Phase 2: try player?.setAudioVolume(Volume(...))  // 0.0...2.0
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        // Phase 2: try player?.setPlaybackRate(...)
    }

    func selectAudioIndex(_ index: Int) {
        selectedAudioIndex = index
        // Phase 2: player?.selectedAudioTrack = …
    }

    func selectSubtitleIndex(_ index: Int?) {
        selectedSubtitleIndex = index ?? -1
        // Phase 2: player?.selectedSubtitleTrack = index.map { … } ?? nil
    }
}
