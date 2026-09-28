import AVFoundation
import Foundation
import MediaPlayer

/// Bridges Native playback state into system Now Playing / audio session.
/// Remote commands remain bound to PlaybackEngine (which routes to Native when active).
@MainActor
final class NativeSystemMediaBridge {
    private let nowPlaying: NowPlayingController
    private let audioSession: AudioSessionCoordinator
    private let logger: LogRouter

    let capabilities = NativeSystemCapabilityStore()

    init(
        nowPlaying: NowPlayingController,
        audioSession: AudioSessionCoordinator,
        logger: LogRouter
    ) {
        self.nowPlaying = nowPlaying
        self.audioSession = audioSession
        self.logger = logger
    }

    func activate(
        metadata: PlexMetadata,
        artworkURL: URL?,
        durationMs: Int64,
        positionMs: Int64,
        rate: Float
    ) {
        do {
            try audioSession.activate()
        } catch {
            logger.playback.error("Native audio session: \(error.localizedDescription)")
        }

        nowPlaying.update(
            metadata: metadata,
            positionMs: positionMs,
            durationMs: durationMs,
            isPlaying: true,
            artworkURL: artworkURL
        )
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        for note in capabilities.current.unavailableNotes {
            logger.playback.info("Native system: \(note)")
        }
    }

    func updateProgress(positionMs: Int64, durationMs: Int64, isPlaying: Bool, rate: Float) {
        nowPlaying.updateProgress(
            positionMs: positionMs,
            durationMs: durationMs,
            isPlaying: isPlaying
        )
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func deactivate() {
        // NowPlaying cleared by engine stop path if desired
    }
}

enum NativePiPBridgePlan {
    static let status = """
    Phase 11: Metal MTKView cannot use AVPictureInPictureController.
    Future: AVSampleBufferDisplayLayer mirror for system PiP.
    Until then, enable PiP by staying on AVPlayer backend.
    """
}
