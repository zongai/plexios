import Foundation
import Observation

/// Phase 1 stub: Native Media Engine is not yet able to decode.
/// Calling `prepare` throws so the router can fall back without hanging.
@Observable
@MainActor
final class NativeMediaBackend: PlayerEngineBackend {
    let backendKind: PlaybackBackend = .nativeMediaEngine
    private(set) var state: MediaEngineSessionState = .idle
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var rate: Float = 1.0

    private let logger: LogRouter

    init(logger: LogRouter) {
        self.logger = logger
    }

    func prepare(request: PlaybackRequest) async throws {
        state = .loading
        logger.playback.info(
            "NativeMediaBackend: not implemented (Phase 1 stub) — \(request.path.rawValue)"
        )
        state = .failed
        throw PlaybackFailure(
            stage: .unknown,
            reason: "Native Media Engine not ready (Phase 1). Fallback to AVPlayer/Transcode.",
            underlying: nil
        )
    }

    func play() {}
    func pause() { state = .paused }
    func stop() async {
        state = .stopped
        positionMs = 0
    }
    func seek(toMs ms: Int64) async { positionMs = ms }
    func setRate(_ rate: Float) { self.rate = rate }
    func selectAudio(streamId: Int) async {}
    func selectSubtitle(streamId: Int?) async {}
}
